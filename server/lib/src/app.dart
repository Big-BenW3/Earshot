/// Assembles the whole server: API, blob claims, feed and web app.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf_static/shelf_static.dart';
import 'package:sui_auth/sui_auth.dart';
import 'package:walrus_blob_check/walrus_blob_check.dart';

import 'api.dart';
import 'auth.dart';
import 'claims.dart';
import 'config.dart';
import 'feed.dart';
import 'store.dart';
import 'views.dart';

const _htmlEscape = HtmlEscape(HtmlEscapeMode.attribute);

class EarshotServer {
  EarshotServer({
    required this.config,
    required this.store,
    WalrusBlobChecker? blobChecker,
    SuiAuth? auth,
    DateTime Function()? clock,
    this.webDir,
    this.landingDir,
  }) : auth = auth ?? buildAuth(config, store.db),
       claims = BlobClaims(
         config: config,
         store: store,
         checker:
             blobChecker ??
             WalrusBlobChecker(
               chain: config.walrusChain,
               aggregatorUrl: config.aggregatorUrl,
             ),
         clock: clock,
       ),
       api = Api(config: config, store: store);

  final Config config;
  final Store store;

  /// Sign in with a Sui wallet: nonces, signature checks and sessions.
  final SuiAuth auth;
  late final SuiAuthHandlers _authHandlers = SuiAuthHandlers(auth);

  /// `POST /api/blobs`: lists blobs hosts stored with their own wallet,
  /// after checking them on Sui.
  final BlobClaims claims;
  final Api api;
  final _signIns = RateLimiter(limit: 30, window: const Duration(minutes: 10));

  /// Built Flutter web app, or null when only the API is needed (tests).
  final String? webDir;

  /// Static marketing page served at "/" (plain HTML, CSS and JS).
  final String? landingDir;

  late final Handler _landingStatic = landingDir == null
      ? (_) => Response.notFound('Not found')
      : createStaticHandler(landingDir!);

  late final Handler _static = webDir == null
      ? (_) => Response.notFound('Not found')
      : createStaticHandler(webDir!, defaultDocument: 'index.html');

  Handler get handler => const Pipeline()
      .addMiddleware(_securityHeaders())
      .addMiddleware(_catchErrors())
      .addMiddleware(_sameOriginWrites())
      .addMiddleware(suiAuthMiddleware(auth))
      .addHandler(_route);

  Future<Response> _route(Request request) async {
    final path = '/${request.url.path}';
    if (path.startsWith('/api/auth/')) {
      if (request.method == 'POST' &&
          (path.endsWith('/nonce') || path.endsWith('/verify'))) {
        final wait = _signIns.take(_clientKey(request));
        if (wait != null) {
          return claimError(
            429,
            'TOO_MANY_REQUESTS',
            'Too many sign-in attempts. Try again later.',
            headers: {'retry-after': '${wait.inSeconds + 1}'},
          );
        }
      }
      final response = await _authHandlers.handler(
        request.change(path: 'api/auth'),
      );
      return response.change(headers: {'cache-control': 'no-store'});
    }
    if (path == '/api/blobs') return claims.handle(request);
    if (path.startsWith('/api/')) return api.router.call(request);
    if (path == '/healthz') return Response.ok('ok');
    if (path.startsWith('/feed/') &&
        (request.method == 'GET' || request.method == 'HEAD')) {
      return _feed(request, path.substring('/feed/'.length));
    }
    if (request.method != 'GET' && request.method != 'HEAD') {
      return Response(405, body: 'Method not allowed');
    }
    return _web(request, path);
  }

  Response _feed(Request request, String file) {
    if (!file.endsWith('.xml')) return Response.notFound('Not found');
    final slug = file.substring(0, file.length - 4);
    final show = store.showBySlug(slug);
    if (show == null) {
      return Response.notFound(
        'No show called "$slug".',
        headers: {'content-type': 'text/plain; charset=utf-8'},
      );
    }
    final views = Views(config, publicBase(config, request));
    final xml = buildFeed(
      views: views,
      show: show,
      episodes: store.episodes(show),
      now: store.now(),
    );
    return Response.ok(
      request.method == 'HEAD' ? null : xml,
      headers: {
        'content-type': 'application/rss+xml; charset=utf-8',
        'cache-control': 'public, max-age=300',
        'access-control-allow-origin': '*',
      },
    );
  }

  Future<Response> _landing(Request request, String path) async {
    final dir = landingDir!;
    if (path == '/') {
      final index = File(p.join(dir, 'index.html'));
      if (!index.existsSync()) return Response.notFound('Not found');
      final base = publicBase(config, request);
      return Response.ok(
        // Attribute-escaped even though publicBase() validates it.
        index.readAsStringSync().replaceAll(
          '__BASE__',
          _htmlEscape.convert(base),
        ),
        headers: {
          'content-type': 'text/html; charset=utf-8',
          'cache-control': 'no-cache',
        },
      );
    }
    final inner = request.change(path: 'landing');
    final response = await _landingStatic(inner);
    if (response.statusCode != 200) return response;
    // Fonts never change; images can be re-shot, so they get a day.
    final maxAge = path.startsWith('/landing/assets/fonts/')
        ? 604800
        : path.startsWith('/landing/assets/img/')
        ? 86400
        : 300;
    return response.change(
      headers: {'cache-control': 'public, max-age=$maxAge'},
    );
  }

  Future<Response> _web(Request request, String path) async {
    if (landingDir != null && (path == '/' || path.startsWith('/landing/'))) {
      return _landing(request, path);
    }
    final dir = webDir;
    if (dir == null) return Response.notFound('Not found');
    final isAppRoute = path == '/' || !p.basename(path).contains('.');
    if (!isAppRoute) {
      final response = await _static(request);
      if (response.statusCode != 404) return _withCaching(path, response);
      if (_fallbackFontPath.hasMatch(path)) return _missingFallbackFont(dir);
      return response;
    }
    final index = File(p.join(dir, 'index.html'));
    if (!index.existsSync()) return Response.notFound('Web app not built');
    final html = _injectMeta(index.readAsStringSync(), request, path);
    return Response.ok(
      html,
      headers: {
        'content-type': 'text/html; charset=utf-8',
        'cache-control': 'no-cache',
      },
    );
  }

  /// A font the Flutter engine asks for when text has characters the
  /// bundled fonts lack (`fontFallbackBaseUrl` in `web/flutter_bootstrap.js`),
  /// for example `/fonts/fallback/notosanssc/v37/<id>.118.woff2`.
  static final _fallbackFontPath = RegExp(
    r'^/fonts/fallback/[a-z0-9]+/v[0-9]+/[A-Za-z0-9_.-]+[.]woff2$',
  );

  /// Answer for fallback fonts this server does not bundle (CJK, Arabic and
  /// so on): a valid font with no glyphs (`fonts/fallback/missing.woff2`).
  ///
  /// The engine retries a failed font download every time it lays out the
  /// text again, hundreds of times in a few seconds. A font it can load,
  /// even one without glyphs, stops that. The characters show as boxes, and
  /// nothing is fetched from a font CDN.
  Response _missingFallbackFont(String webDir) {
    final file = File(p.join(webDir, 'fonts', 'fallback', 'missing.woff2'));
    if (!file.existsSync()) return Response.notFound('Not found');
    return Response.ok(
      file.readAsBytesSync(),
      headers: {
        'content-type': 'font/woff2',
        // Shorter than real fonts, so a font added later is picked up.
        'cache-control': 'public, max-age=86400',
        'x-earshot-font': 'no-glyphs',
      },
    );
  }

  Response _withCaching(String path, Response response) {
    // The engine's fallback fonts (Roboto, Noto), served from here instead
    // of fonts.gstatic.com; the versioned paths never change.
    if (path.startsWith('/fonts/fallback/')) {
      return response.change(
        headers: {'cache-control': 'public, max-age=604800'},
      );
    }
    return response.change(headers: {'cache-control': 'no-cache'});
  }

  /// Fills page-specific title and Open Graph tags so shared links preview
  /// well. Replaces the block between `<!--meta-->` and `<!--/meta-->`.
  String _injectMeta(String html, Request request, String path) {
    const start = '<!--meta-->';
    const end = '<!--/meta-->';
    final a = html.indexOf(start);
    final b = html.indexOf(end);
    if (a < 0 || b < a) return html;

    final base = publicBase(config, request);
    final views = Views(config, base);
    var title = 'Earshot';
    var description =
        'An audio shelf for sermons, lectures, community podcasts and talks.';
    String? image = '$base/icons/og-image.png';
    var url = '$base$path';

    final match = RegExp(
      r'^/s/([a-z0-9-]+)(?:/e/([a-z0-9]+))?/?$',
    ).firstMatch(path);
    if (match != null) {
      final show = store.showBySlug(match.group(1)!);
      if (show != null) {
        title = '${show.name} on Earshot';
        description = show.description.isEmpty
            ? 'Listen to ${show.name} by ${show.author}.'
            : show.description;
        image = views.coverUrl(show) ?? image;
        url = views.showUrl(show);
        final episodeId = match.group(2);
        if (episodeId != null) {
          final e = store.episode(show.id, episodeId);
          if (e != null && e.isPublic(store.now())) {
            title = '${e.title} · ${show.name}';
            if (e.description.isNotEmpty) description = e.description;
            url = views.episodeUrl(show, e);
          }
        }
      }
    }
    if (description.length > 200) {
      description = '${description.substring(0, 197).trimRight()}...';
    }
    String esc(String v) => _htmlEscape.convert(v);
    final tags = StringBuffer()
      ..writeln('<title>${esc(title)}</title>')
      ..writeln('  <meta name="description" content="${esc(description)}">')
      ..writeln('  <meta property="og:type" content="website">')
      ..writeln('  <meta property="og:site_name" content="Earshot">')
      ..writeln('  <meta property="og:title" content="${esc(title)}">')
      ..writeln(
        '  <meta property="og:description" content="${esc(description)}">',
      )
      ..writeln('  <meta property="og:url" content="${esc(url)}">')
      ..writeln('  <meta property="og:image" content="${esc(image)}">')
      ..writeln('  <meta name="twitter:card" content="summary">')
      ..write('  ');
    final before = html.substring(0, a + start.length);
    return '$before\n  $tags${html.substring(b)}';
  }

  /// Defence in depth for cookie sessions: state-changing requests that
  /// carry an Origin must come from Earshot's own origin. (SameSite=Lax and
  /// CORS preflights already stop most cross-site writes.)
  Middleware _sameOriginWrites() =>
      (inner) => (request) {
        final unsafe = !const {
          'GET',
          'HEAD',
          'OPTIONS',
        }.contains(request.method);
        final path = request.url.path;
        final guarded = path.startsWith('api/');
        final origin = request.headers['origin'];
        if (unsafe &&
            guarded &&
            origin != null &&
            !auth.config.allowedOrigins.contains(origin)) {
          return apiError(403, 'Requests must come from Earshot itself.');
        }
        return inner(request);
      };

  String _clientKey(Request request) {
    if (config.trustProxy) {
      final forwarded = request.headers['x-forwarded-for']
          ?.split(',')
          .first
          .trim();
      if (forwarded != null &&
          forwarded.length <= 45 &&
          InternetAddress.tryParse(forwarded) != null) {
        return forwarded;
      }
    }
    final info = request.context['shelf.io.connection_info'];
    return info is HttpConnectionInfo ? info.remoteAddress.address : 'local';
  }

  Middleware _catchErrors() =>
      (inner) => (request) async {
        try {
          return await inner(request);
        } catch (_) {
          return apiError(500, 'Something went wrong. Try again.');
        }
      };

  Middleware _securityHeaders() =>
      (inner) => (request) async {
        final response = await inner(request);
        return response.change(
          headers: {
            'x-content-type-options': 'nosniff',
            'referrer-policy': 'strict-origin-when-cross-origin',
            'x-frame-options': 'SAMEORIGIN',
          },
        );
      };
}
