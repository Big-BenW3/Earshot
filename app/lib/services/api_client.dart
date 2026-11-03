import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/models.dart';

class ApiException implements Exception {
  ApiException(this.status, this.message, {this.fields = const {}, this.code});

  final int status;
  final String message;
  final Map<String, String> fields;

  /// Machine-readable reason from errors in the `{"error": {"status": …}}`
  /// shape, such as `ALREADY_CLAIMED`.
  final String? code;

  bool get notFound => status == 404;
  bool get unauthorized => status == 401 || status == 403;
  bool get offline => status == 0;

  @override
  String toString() => message;
}

/// Client for Earshot's own JSON API (metadata only; files go to Walrus
/// from the host's wallet through Dartus, and only their Blob object IDs
/// come here).
class EarshotApi {
  EarshotApi({
    required this.base,
    http.Client? client,
    this.requestTimeout = const Duration(seconds: 30),
  }) : _client = client ?? http.Client();

  /// The site origin, e.g. `http://localhost:8095`.
  final Uri base;
  final Duration requestTimeout;
  final http.Client _client;

  Uri _uri(String path) => base.resolve(path);

  Future<Map<String, Object?>> _send(
    String method,
    String path, {
    Object? body,
  }) async {
    final request = http.Request(method, _uri(path));
    request.headers['accept'] = 'application/json';
    if (body != null) {
      request.headers['content-type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    final http.Response response;
    try {
      response = await _client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(requestTimeout);
    } catch (_) {
      throw ApiException(
        0,
        'Could not reach Earshot. Check your connection and try again.',
      );
    }
    Map<String, Object?> json = const {};
    var validJson = false;
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, Object?>) {
        json = decoded;
        validJson = true;
      }
    } catch (_) {}
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (!validJson) {
        throw ApiException(
          502,
          'Earshot returned an unreadable response. Try again.',
        );
      }
      return json;
    }
    final fields = <String, String>{
      for (final e in ((json['fields'] as Map?) ?? const {}).entries)
        '${e.key}': '${e.value}',
    };
    // Earshot's API sends {"error": "text"}; sign-in and claim errors use
    // {"error": {"status": "CODE", "message": "text"}}.
    final error = json['error'];
    final message = error is String
        ? error
        : error is Map && error['message'] is String
        ? error['message'] as String
        : 'Something went wrong (${response.statusCode}).';
    throw ApiException(
      response.statusCode,
      message,
      fields: fields,
      code: error is Map && error['status'] is String
          ? error['status'] as String
          : null,
    );
  }

  /// Lists a blob the host stored with their own wallet. The server checks
  /// the Blob object on Sui (certified, owned by the signed-in address,
  /// within limits, an accepted type, not listed before).
  Future<ClaimedBlob> claimBlob(String objectId) async => ClaimedBlob.fromJson(
    await _send('POST', '/api/blobs', body: {'objectId': objectId}),
  );

  Future<AppConfig> config() async =>
      AppConfig.fromJson(await _send('GET', '/api/config'));

  Future<CreatedShow> createShow({
    required String name,
    required String author,
    required String description,
    required String language,
    required String category,
    required bool explicit,
  }) async => CreatedShow.fromJson(
    await _send(
      'POST',
      '/api/shows',
      body: {
        'name': name,
        'author': author,
        'description': description,
        'language': language,
        'category': category,
        'explicit': explicit,
      },
    ),
  );

  Future<ShowPage> show(String slug) async => ShowPage.fromJson(
    await _send('GET', '/api/shows/${Uri.encodeComponent(slug)}'),
  );

  Future<(Show, Episode)> episode(String slug, String id) async {
    final j = await _send(
      'GET',
      '/api/shows/${Uri.encodeComponent(slug)}/episodes/${Uri.encodeComponent(id)}',
    );
    return (
      Show.fromJson(j['show'] as Map<String, Object?>),
      Episode.fromJson(j['episode'] as Map<String, Object?>),
    );
  }

  /// The signed-in host's shows (`GET /api/my/shows`), on any device.
  Future<List<MyShow>> myShows() async {
    final j = await _send('GET', '/api/my/shows');
    return [
      for (final s in j['shows'] as List)
        MyShow.fromJson(s as Map<String, Object?>),
    ];
  }

  String _admin(String slug) => '/api/admin/shows/${Uri.encodeComponent(slug)}';

  Future<ShowPage> adminShow(String slug) async =>
      ShowPage.fromJson(await _send('GET', _admin(slug)));

  Future<ShowPage> updateShow(String slug, Map<String, Object?> fields) async =>
      ShowPage.fromJson(await _send('PATCH', _admin(slug), body: fields));

  Future<Episode> createEpisode(
    String slug, {
    required String title,
    required String description,
    required String blobId,
    required DateTime publishAt,
    int? durationSeconds,
  }) async {
    final j = await _send(
      'POST',
      '${_admin(slug)}/episodes',
      body: {
        'title': title,
        'description': description,
        'blobId': blobId,
        'publishAt': publishAt.toUtc().toIso8601String(),
        'durationSeconds': durationSeconds,
      },
    );
    return Episode.fromJson(j['episode'] as Map<String, Object?>);
  }

  Future<Episode> updateEpisode(
    String slug,
    String id,
    Map<String, Object?> fields,
  ) async {
    final j = await _send(
      'PATCH',
      '${_admin(slug)}/episodes/${Uri.encodeComponent(id)}',
      body: fields,
    );
    return Episode.fromJson(j['episode'] as Map<String, Object?>);
  }

  Future<ShowPage> pin(String slug, String? episodeId) async =>
      ShowPage.fromJson(
        await _send(
          'PUT',
          '${_admin(slug)}/pin',
          body: {'episodeId': episodeId},
        ),
      );

  Future<ShowPage> reorder(String slug, List<String> ids) async =>
      ShowPage.fromJson(
        await _send('PUT', '${_admin(slug)}/order', body: {'episodeIds': ids}),
      );
}
