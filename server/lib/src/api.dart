/// JSON API for show and episode metadata.
library;

import 'dart:async';
import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'config.dart';
import 'claims.dart' show RateLimiter;
import 'package:sui_auth/sui_auth.dart' show SuiAuthRequest;
import 'sniff.dart';
import 'store.dart';
import 'validation.dart';
import 'views.dart';

const _maxJsonBytes = 64 * 1024;

Response jsonResponse(Object? body, {int status = 200}) => Response(
  status,
  body: jsonEncode(body),
  headers: {
    'content-type': 'application/json; charset=utf-8',
    'cache-control': 'no-store',
  },
);

Response apiError(int status, String message, {Map<String, String>? fields}) =>
    jsonResponse({
      'error': message,
      if (fields != null && fields.isNotEmpty) 'fields': fields,
    }, status: status);

class _HttpError implements Exception {
  _HttpError(this.status, this.message);
  final int status;
  final String message;
}

class Api {
  Api({required this.config, required this.store});

  final Config config;
  final Store store;
  final _showCreates = RateLimiter(limit: 20, window: const Duration(hours: 1));

  Router get router {
    final r = Router(notFoundHandler: (_) => apiError(404, 'Not found.'));
    r.get('/api/config', _config);
    r.get('/api/my/shows', _guard(_myShows));
    r.post('/api/shows', _guard(_createShow));
    r.get('/api/shows/<slug>', _guard(_publicShow));
    r.get('/api/shows/<slug>/episodes/<id>', _guard(_publicEpisode));
    r.get('/api/admin/shows/<slug>', _guard(_adminShow));
    r.patch('/api/admin/shows/<slug>', _guard(_updateShow));
    r.post('/api/admin/shows/<slug>/episodes', _guard(_createEpisode));
    r.patch('/api/admin/shows/<slug>/episodes/<id>', _guard(_updateEpisode));
    r.put('/api/admin/shows/<slug>/pin', _guard(_pin));
    r.put('/api/admin/shows/<slug>/order', _guard(_order));
    return r;
  }

  /// Wraps a handler taking `(request, ...routeParams)` and maps known
  /// errors to JSON responses.
  Handler _guard(Function handler) => (Request request) async {
    try {
      final args = <Object?>[request, ...request.params.values];
      return await (Function.apply(handler, args) as FutureOr<Response>);
    } on ValidationException catch (e) {
      return apiError(400, e.message, fields: e.errors);
    } on _HttpError catch (e) {
      return apiError(e.status, e.message);
    } on TimeoutException {
      return apiError(408, 'The request took too long. Try again.');
    } on FormatException {
      return apiError(400, 'The request body is not valid JSON.');
    }
  };

  Future<Map<String, Object?>> _readJson(Request request) async {
    final length = request.contentLength;
    if (length != null && length > _maxJsonBytes) {
      throw _HttpError(413, 'The request is too large.');
    }
    final bytes = <int>[];
    await for (final chunk in request.read().timeout(
      const Duration(seconds: 30),
    )) {
      if (bytes.length + chunk.length > _maxJsonBytes) {
        throw _HttpError(413, 'The request is too large.');
      }
      bytes.addAll(chunk);
    }
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Expected a JSON object');
    }
    return decoded;
  }

  ShowRecord _requireShow(String slug) {
    final show = store.showBySlug(slug);
    if (show == null) throw _HttpError(404, 'This show does not exist.');
    return show;
  }

  /// The signed-in host's verified address, or 401.
  String _requireSignedIn(Request request) {
    final address = request.suiAddress;
    if (address == null) {
      throw _HttpError(401, 'Sign in with your Sui wallet to continue.');
    }
    return address;
  }

  /// The show named in the URL, owned by the signed-in host (401 / 403).
  ShowRecord _requireOwner(Request request, String slug) {
    final address = _requireSignedIn(request);
    final show = _requireShow(slug);
    if (show.ownerAddress != address) {
      throw _HttpError(403, 'This show belongs to another account.');
    }
    return show;
  }

  Views _views(Request request) => Views(config, publicBase(config, request));

  Response _config(Request request) => jsonResponse({
    'aggregatorUrl': config.aggregatorUrl.toString(),
    'network': config.network,
    'epochs': config.epochs,
    'maxUploadMb': config.maxUploadMb,
    'maxImageMb': maxImageBytes ~/ (1024 * 1024),
    'publicBaseUrl': publicBase(config, request),
    'categories': podcastCategories,
    'suiChain': config.suiChain.id,
  });

  /// `GET /api/my/shows`: the signed-in host's shows, on any device.
  Response _myShows(Request request) {
    final address = _requireSignedIn(request);
    final views = _views(request);
    return jsonResponse({
      'address': address,
      'shows': [
        for (final show in store.showsOwnedBy(address))
          {
            ...views.show(show, admin: true),
            'episodeCount': store.episodeCount(show),
          },
      ],
    });
  }

  Future<Response> _createShow(Request request) async {
    // The owner is the session's verified address, never a value from the body.
    final owner = _requireSignedIn(request);
    if (_showCreates.take(owner) != null) {
      throw _HttpError(429, 'Too many shows created. Try again later.');
    }
    final f = FieldReader(await _readJson(request));
    final name = f.text(
      'name',
      label: 'Show name',
      max: maxNameLength,
      required: true,
    );
    final author = f.text(
      'author',
      label: 'Author',
      max: maxAuthorLength,
      required: true,
    );
    final description = f.text(
      'description',
      label: 'Description',
      max: maxShowDescriptionLength,
    );
    final language = f.language('language');
    final category = f.category('category');
    final explicit = f.boolean('explicit', label: 'Explicit');
    f.check();
    final show = store.createShow(
      ownerAddress: owner,
      name: name!,
      description: description ?? '',
      author: author!,
      language: language ?? 'en',
      category: category ?? 'Society & Culture',
      explicit: explicit ?? false,
    );
    final views = _views(request);
    return jsonResponse({
      'show': views.show(show, admin: true),
      'publicUrl': views.showUrl(show),
      'feedUrl': views.feedUrl(show),
    }, status: 201);
  }

  Map<String, Object?> _showPayload(
    Request request,
    ShowRecord show, {
    required bool admin,
  }) {
    final views = _views(request);
    final now = store.now();
    final episodes = store.episodes(show, includePrivate: admin);
    return {
      'show': views.show(show, admin: admin),
      'episodes': [
        for (final e in episodes)
          views.episode(show, e, admin: admin, now: now),
      ],
    };
  }

  Response _publicShow(Request request, String slug) =>
      jsonResponse(_showPayload(request, _requireShow(slug), admin: false));

  Response _publicEpisode(Request request, String slug, String id) {
    final show = _requireShow(slug);
    final episode = store.episode(show.id, id);
    if (episode == null || !episode.isPublic(store.now())) {
      throw _HttpError(404, 'This episode is not available.');
    }
    final views = _views(request);
    return jsonResponse({
      'show': views.show(show),
      'episode': views.episode(show, episode),
    });
  }

  Response _adminShow(Request request, String slug) => jsonResponse(
    _showPayload(request, _requireOwner(request, slug), admin: true),
  );

  Future<Response> _updateShow(Request request, String slug) async {
    final show = _requireOwner(request, slug);
    final f = FieldReader(await _readJson(request));
    final name = f.has('name')
        ? f.text('name', label: 'Show name', max: maxNameLength, required: true)
        : null;
    final author = f.has('author')
        ? f.text(
            'author',
            label: 'Author',
            max: maxAuthorLength,
            required: true,
          )
        : null;
    final description = f.text(
      'description',
      label: 'Description',
      max: maxShowDescriptionLength,
    );
    final language = f.language('language');
    final category = f.category('category');
    final explicit = f.boolean('explicit', label: 'Explicit');
    String? orderMode;
    if (f.has('orderMode')) {
      final raw = f.json['orderMode'];
      if (raw == 'newest' || raw == 'custom') {
        orderMode = raw as String;
      } else {
        f.errors['orderMode'] = 'Order must be newest or custom.';
      }
    }
    String? coverBlobId;
    String? coverMime;
    if (f.has('coverBlobId')) {
      final raw = f.json['coverBlobId'];
      final upload = raw is String
          ? store.upload(show.ownerAddress, raw)
          : null;
      if (upload == null || upload.kind != UploadKind.image) {
        f.errors['coverBlobId'] = 'Upload the cover image again.';
      } else {
        coverBlobId = upload.blobId;
        coverMime = upload.mime;
      }
    }
    f.check();
    final updated = store.updateShow(
      show,
      name: name,
      description: description,
      author: author,
      language: language,
      category: category,
      explicit: explicit,
      coverBlobId: coverBlobId,
      coverMime: coverMime,
      orderMode: orderMode,
    );
    return jsonResponse(_showPayload(request, updated, admin: true));
  }

  Future<Response> _createEpisode(Request request, String slug) async {
    final show = _requireOwner(request, slug);
    final f = FieldReader(await _readJson(request));
    final title = f.text(
      'title',
      label: 'Title',
      max: maxTitleLength,
      required: true,
    );
    final description = f.text(
      'description',
      label: 'Description',
      max: maxEpisodeDescriptionLength,
    );
    final publishAt = f.dateTime('publishAt', label: 'Publish date');
    final (_, duration) = f.nullableInt(
      'durationSeconds',
      label: 'Duration',
      min: 0,
      max: maxDurationSeconds,
    );
    final blobId = f.json['blobId'];
    final upload = blobId is String
        ? store.upload(show.ownerAddress, blobId)
        : null;
    if (upload == null || upload.kind != UploadKind.audio) {
      f.errors['blobId'] = 'Upload the audio file first.';
    }
    f.check();
    final episode = store.createEpisode(
      show: show,
      upload: upload!,
      title: title!,
      description: description ?? '',
      publishAt: publishAt ?? store.now(),
      durationSeconds: duration,
    );
    final views = _views(request);
    return jsonResponse({
      'episode': views.episode(show, episode, admin: true, now: store.now()),
    }, status: 201);
  }

  Future<Response> _updateEpisode(
    Request request,
    String slug,
    String id,
  ) async {
    final show = _requireOwner(request, slug);
    final episode = store.episode(show.id, id);
    if (episode == null) throw _HttpError(404, 'This episode does not exist.');
    final f = FieldReader(await _readJson(request));
    final title = f.has('title')
        ? f.text('title', label: 'Title', max: maxTitleLength, required: true)
        : null;
    final description = f.text(
      'description',
      label: 'Description',
      max: maxEpisodeDescriptionLength,
    );
    final publishAt = f.dateTime('publishAt', label: 'Publish date');
    final hidden = f.boolean('hidden', label: 'Hidden');
    final (hasDuration, duration) = f.nullableInt(
      'durationSeconds',
      label: 'Duration',
      min: 0,
      max: maxDurationSeconds,
    );
    f.check();
    final updated = store.updateEpisode(
      episode,
      title: title,
      description: description,
      publishAt: publishAt,
      hidden: hidden,
      setDuration: hasDuration,
      durationSeconds: duration,
    );
    if (updated.hidden) {
      store.unpinIfCurrent(show, updated.id);
    }
    final views = _views(request);
    final fresh = store.showBySlug(slug)!;
    return jsonResponse({
      'episode': views.episode(fresh, updated, admin: true, now: store.now()),
    });
  }

  Future<Response> _pin(Request request, String slug) async {
    final show = _requireOwner(request, slug);
    final json = await _readJson(request);
    final id = json['episodeId'];
    if (id != null) {
      final episode = id is String ? store.episode(show.id, id) : null;
      if (episode == null) {
        throw ValidationException({
          'episodeId': 'This episode does not exist.',
        });
      }
      if (episode.hidden) {
        throw ValidationException({
          'episodeId': 'Show the episode before pinning it.',
        });
      }
    }
    store.setPinned(show, id as String?);
    return jsonResponse(
      _showPayload(request, store.showBySlug(slug)!, admin: true),
    );
  }

  Future<Response> _order(Request request, String slug) async {
    final show = _requireOwner(request, slug);
    final json = await _readJson(request);
    final ids = json['episodeIds'];
    if (ids is! List || ids.any((e) => e is! String)) {
      throw ValidationException({
        'episodeIds': 'Send the episode IDs in the new order.',
      });
    }
    store.reorder(show, ids.cast<String>());
    return jsonResponse(
      _showPayload(request, store.showBySlug(slug)!, admin: true),
    );
  }
}
