/// Server configuration, read from environment variables only.
library;

import 'package:sui_auth/sui_auth.dart' show SuiChain;
import 'package:walrus_blob_check/walrus_blob_check.dart' show WalrusChain;

/// Largest accepted cover image, in bytes. Podcast apps want square art
/// between 1400 and 3000 pixels, which fits easily in 5 MiB as JPEG or PNG.
const maxImageBytes = 5 * 1024 * 1024;

class Config {
  Config({
    this.port = 8095,
    Uri? aggregatorUrl,
    this.epochs = 26,
    this.maxUploadMb = 100,
    this.dataDir = 'data',
    this.publicBaseUrl,
    this.trustProxy = false,
    this.suiChain = SuiChain.testnet,
    this.claimsPerWindow = 30,
    this.claimWindow = const Duration(minutes: 10),
  }) : aggregatorUrl =
           aggregatorUrl ??
           Uri.parse(WalrusChain.parse(suiChain.id).aggregator);

  /// Builds a config from `Platform.environment` (or any map, for tests).
  factory Config.fromEnvironment(Map<String, String> env) {
    String? read(String key) {
      final value = env[key]?.trim();
      return (value == null || value.isEmpty) ? null : value;
    }

    int readInt(String key, int fallback, {int min = 1, int? max}) {
      final raw = read(key);
      if (raw == null) return fallback;
      final value = int.tryParse(raw);
      if (value == null || value < min || (max != null && value > max)) {
        throw FormatException('$key must be a whole number >= $min', raw);
      }
      return value;
    }

    Uri? readUrl(String key) {
      final raw = read(key);
      if (raw == null) return null;
      final uri = Uri.tryParse(raw);
      if (uri == null ||
          !{'http', 'https'}.contains(uri.scheme) ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty) {
        throw FormatException('$key must be an absolute http(s) URL', raw);
      }
      if (key == 'PUBLIC_BASE_URL' &&
          ((uri.path.isNotEmpty && uri.path != '/') ||
              uri.hasQuery ||
              uri.hasFragment)) {
        throw const FormatException(
          'PUBLIC_BASE_URL must be an origin without a path, query or fragment',
        );
      }
      return uri;
    }

    return Config(
      port: readInt('PORT', 8095, max: 65535),
      aggregatorUrl: readUrl('AGGREGATOR_URL'),
      epochs: readInt('EPOCHS', 26, max: 53),
      maxUploadMb: readInt('MAX_UPLOAD_MB', 100, max: 100),
      dataDir: read('DATA_DIR') ?? 'data',
      publicBaseUrl: readUrl('PUBLIC_BASE_URL'),
      trustProxy: read('TRUST_PROXY')?.toLowerCase() == 'true',
      suiChain: _chain(read('SUI_CHAIN')),
      claimsPerWindow: readInt('CLAIM_LIMIT', 30, max: 10000),
    );
  }

  final int port;

  /// Where listeners, podcast apps and the server read blobs.
  final Uri aggregatorUrl;

  /// Storage epochs the app suggests for each upload. Hosts pay for their
  /// own storage, so this is a suggestion sent in `/api/config`.
  final int epochs;
  final int maxUploadMb;
  final String dataDir;
  final Uri? publicBaseUrl;

  /// Trust `X-Forwarded-Host` and `X-Forwarded-Proto`. Only set this when a
  /// reverse proxy you control overwrites those headers.
  final bool trustProxy;

  /// The Sui network hosts sign in and pay on (`SUI_CHAIN=testnet|mainnet`).
  final SuiChain suiChain;

  /// Abuse limit: blob claims one address (and one client IP) may make per
  /// [claimWindow] (`CLAIM_LIMIT`). Each claim makes the server read Sui and
  /// the aggregator, so it is rate limited even though hosts pay for storage.
  final int claimsPerWindow;
  final Duration claimWindow;

  /// The Walrus deployment on [suiChain], for checking blobs on Sui.
  WalrusChain get walrusChain => WalrusChain.parse(suiChain.id);

  /// The origin hosts sign in to. It is the domain inside the signed
  /// message, so it must be exactly the URL people open.
  String get signInOrigin =>
      (publicBaseUrl ?? Uri.parse('http://localhost:$port')).toString();

  static SuiChain _chain(String? raw) {
    if (raw == null) return SuiChain.testnet;
    final chain = SuiChain.tryParse(raw);
    if (chain != SuiChain.testnet && chain != SuiChain.mainnet) {
      throw FormatException('SUI_CHAIN must be testnet or mainnet', raw);
    }
    return chain!;
  }

  int get maxAudioBytes => maxUploadMb * 1024 * 1024;

  /// `testnet`, `mainnet` or `custom`, judged from the aggregator host.
  String get network {
    final host = aggregatorUrl.host;
    if (host.contains('testnet')) return 'testnet';
    if (host.contains('mainnet')) return 'mainnet';
    return 'custom';
  }

  /// Public URL of a blob on the configured aggregator.
  Uri blobUrl(String blobId) {
    final base = aggregatorUrl.toString().replaceAll(RegExp(r'/+$'), '');
    return Uri.parse('$base/v1/blobs/${Uri.encodeComponent(blobId)}');
  }

  /// A summary for logs.
  String describe() =>
      'port=$port network=$network aggregator=$aggregatorUrl '
      'epochs=$epochs maxUploadMb=$maxUploadMb dataDir=$dataDir '
      'publicBaseUrl=${publicBaseUrl ?? '(from request)'} '
      'trustProxy=$trustProxy suiChain=${suiChain.id} '
      'claimLimit=$claimsPerWindow/${claimWindow.inMinutes}min';
}
