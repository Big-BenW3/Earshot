/// JSON shapes and public URLs shared by the API, the feed and page metadata.
library;

import 'package:shelf/shelf.dart';

import 'config.dart';
import 'store.dart';

/// Host names we accept from request headers: letters, digits, dots and
/// hyphens, an optional port, at most 253 characters for the name.
final _hostPattern = RegExp(
  r'^[A-Za-z0-9](?:[A-Za-z0-9.-]{0,251}[A-Za-z0-9])?(?::[0-9]{1,5})?$',
);

/// The site's public origin, used in feeds, share links and page metadata.
///
/// `PUBLIC_BASE_URL` wins when set (production must set it). Otherwise the
/// request's `Host` is used, or `X-Forwarded-Host` and `X-Forwarded-Proto`
/// when `TRUST_PROXY=true`. Header values are validated strictly; anything
/// unexpected falls back to `http://localhost:<port>`, so a hostile header
/// can never reach a page, a feed or a cache.
String publicBase(Config config, Request request) {
  final configured = config.publicBaseUrl;
  if (configured != null) {
    return configured.toString().replaceAll(RegExp(r'/+$'), '');
  }
  final fallback = 'http://localhost:${config.port}';
  String? first(String? v) => v?.split(',').first.trim();

  final host = config.trustProxy
      ? first(request.headers['x-forwarded-host']) ?? request.headers['host']
      : request.headers['host'];
  final proto = config.trustProxy
      ? first(request.headers['x-forwarded-proto']) ??
            request.requestedUri.scheme
      : request.requestedUri.scheme;

  if (host == null || host.length > 260 || !_hostPattern.hasMatch(host)) {
    return fallback;
  }
  final scheme = proto.toLowerCase();
  if (scheme != 'http' && scheme != 'https') return fallback;
  return '$scheme://${host.toLowerCase()}';
}

class Views {
  Views(this.config, this.base);

  final Config config;
  final String base;

  String _seg(String v) => Uri.encodeComponent(v);

  String showUrl(ShowRecord s) => '$base/s/${_seg(s.slug)}';
  String episodeUrl(ShowRecord s, EpisodeRecord e) =>
      '$base/s/${_seg(s.slug)}/e/${_seg(e.id)}';
  String feedUrl(ShowRecord s) => '$base/feed/${_seg(s.slug)}.xml';

  String? coverUrl(ShowRecord s) =>
      s.coverBlobId == null ? null : config.blobUrl(s.coverBlobId!).toString();

  Map<String, Object?> show(ShowRecord s, {bool admin = false}) => {
    'slug': s.slug,
    'name': s.name,
    'description': s.description,
    'author': s.author,
    'language': s.language,
    'category': s.category,
    'explicit': s.explicit,
    'coverBlobId': s.coverBlobId,
    'coverUrl': coverUrl(s),
    'orderMode': s.orderMode,
    'pinnedEpisodeId': s.pinnedEpisodeId,
    'publicUrl': showUrl(s),
    'feedUrl': feedUrl(s),
    'createdAt': s.createdAt.toIso8601String(),
    'updatedAt': s.updatedAt.toIso8601String(),
  };

  Map<String, Object?> episode(
    ShowRecord s,
    EpisodeRecord e, {
    bool admin = false,
    DateTime? now,
  }) => {
    'id': e.id,
    'title': e.title,
    'description': e.description,
    'publishAt': e.publishAt.toIso8601String(),
    'durationSeconds': e.durationSeconds,
    'blobId': e.blobId,
    'mime': e.mime,
    'sizeBytes': e.sizeBytes,
    'endEpoch': e.endEpoch,
    'audioUrl': config.blobUrl(e.blobId).toString(),
    'pageUrl': episodeUrl(s, e),
    'pinned': s.pinnedEpisodeId == e.id,
    if (admin) 'hidden': e.hidden,
    if (admin) 'scheduled': e.publishAt.isAfter(now ?? DateTime.now().toUtc()),
  };
}
