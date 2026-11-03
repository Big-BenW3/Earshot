import 'dart:async';
import 'dart:io';

import 'package:earshot_server/earshot_server.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;

/// Finds the built web app: `./web` next to the binary in the Docker image,
/// otherwise `../app/build/web` when run from the source tree.
String? _findWebDir() {
  final candidates = [
    p.join(p.dirname(Platform.resolvedExecutable), 'web'),
    p.join(Directory.current.path, 'web'),
    p.join(Directory.current.path, '..', 'app', 'build', 'web'),
    p.join(Directory.current.path, 'app', 'build', 'web'),
  ];
  for (final dir in candidates) {
    if (File(p.join(dir, 'index.html')).existsSync()) return p.normalize(dir);
  }
  return null;
}

/// The static landing page: `./landing` next to the binary, or the
/// repository's `landing/` folder.
String? _findLandingDir() {
  final candidates = [
    p.join(p.dirname(Platform.resolvedExecutable), 'landing'),
    p.join(Directory.current.path, 'landing'),
    p.join(Directory.current.path, '..', 'landing'),
  ];
  for (final dir in candidates) {
    if (File(p.join(dir, 'index.html')).existsSync()) return p.normalize(dir);
  }
  return null;
}

Future<void> main() async {
  final Config config;
  try {
    config = Config.fromEnvironment(Platform.environment);
  } on FormatException catch (e) {
    stderr.writeln('Config error: ${e.message} (${e.source})');
    exitCode = 64;
    return;
  }

  final Store store;
  try {
    store = Store.open(config.dataDir);
  } on StateError catch (e) {
    stderr.writeln(e.message);
    exitCode = 78;
    return;
  }
  final webDir = _findWebDir();
  final landingDir = _findLandingDir();
  final server = EarshotServer(
    config: config,
    store: store,
    webDir: webDir,
    landingDir: landingDir,
  );

  final handler = const Pipeline()
      .addMiddleware(logRequests())
      .addHandler(server.handler);

  final http = await io.serve(handler, InternetAddress.anyIPv4, config.port);
  // Large uploads stream through slowly on poor connections.
  http.idleTimeout = const Duration(minutes: 2);
  http.autoCompress = true;

  stdout.writeln('Earshot listening on http://localhost:${http.port}');
  stdout.writeln(config.describe());
  if (config.publicBaseUrl == null) {
    stderr.writeln(
      'Warning: PUBLIC_BASE_URL is not set. Sign-in messages are bound to '
      'http://localhost:${config.port}, and links in feeds and previews use '
      'the validated Host header. Set PUBLIC_BASE_URL to the exact URL people '
      'open in production.',
    );
  }
  stdout.writeln('Web app: ${webDir ?? 'not built (API only)'}');
  stdout.writeln('Landing: ${landingDir ?? 'none (the app serves /)'}');

  Future<void> purge() async {
    try {
      await server.auth.purgeExpired();
    } catch (_) {
      stderr.writeln('Could not remove expired sign-in records.');
    }
  }

  await purge();
  final cleanup = Timer.periodic(
    const Duration(hours: 1),
    (_) => unawaited(purge()),
  );
  var closing = false;
  Future<void> shutdown(ProcessSignal _) async {
    if (closing) return;
    closing = true;
    cleanup.cancel();
    await http.close();
    store.close();
    exit(0);
  }

  ProcessSignal.sigint.watch().listen(shutdown);

  if (!Platform.isWindows) {
    ProcessSignal.sigterm.watch().listen(shutdown);
  }
}
