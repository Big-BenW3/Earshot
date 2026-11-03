import 'dart:typed_data';

import 'package:dartus/dartus.dart';
import 'package:http/http.dart' as http;

import 'platform/progress_client.dart';

typedef ClientFactory =
    http.Client Function({
      ProgressCallback? onUpload,
      ProgressCallback? onDownload,
    });

enum BlobAvailability { available, missing, unknown }

class WalrusException implements Exception {
  WalrusException(this.message, {this.code = 0});
  final String message;
  final int code;

  bool get missing => code == 404;

  @override
  String toString() => message;
}

class DownloadCancellation {
  bool _cancelled = false;
  void Function()? _abort;
  void cancel() {
    _cancelled = true;
    _abort?.call();
  }
}

/// Every Walrus read in the app goes through Dartus (`WalrusClient` in
/// HTTP mode, from the aggregator in server config). Writes are paid for by
/// the host's wallet and go through `WalletStorage` (Dartus's
/// `WalrusWriter`) instead.
///
/// The one exception is audio playback, which points an `<audio>` element at
/// the aggregator URL so the browser can stream with range requests.
class WalrusService {
  WalrusService({required this.aggregatorBase, ClientFactory? clientFactory})
    : _factory = clientFactory ?? createProgressClient {
    _readerHttp = _factory();
    _reader = _client(_readerHttp, cacheMaxSize: 64, seconds: 60);
  }

  final Uri aggregatorBase;
  final ClientFactory _factory;
  late final http.Client _readerHttp;
  late final WalrusClient _reader;

  /// A read-only client. Dartus still asks for a publisher URL; nothing is
  /// ever written through it.
  WalrusClient _client(
    http.Client httpClient, {
    required int cacheMaxSize,
    required int seconds,
  }) => WalrusClient(
    publisherBaseUrl: aggregatorBase,
    aggregatorBaseUrl: aggregatorBase,
    httpClient: httpClient,
    cacheMaxSize: cacheMaxSize,
    timeout: Duration(seconds: seconds),
  );

  /// Reads a small blob (cover art) with Dartus `getBlob`, cached in memory.
  Future<Uint8List> readImage(String blobId) async {
    try {
      return await _reader.getBlob(blobId);
    } on WalrusApiError catch (e) {
      throw WalrusException(_friendly(e), code: e.code);
    } catch (_) {
      throw WalrusException('Could not load the image.');
    }
  }

  /// Downloads a whole episode with Dartus `getBlob` for "Download episode".
  Future<Uint8List> download(
    String blobId, {
    ProgressCallback? onProgress,
    DownloadCancellation? cancellation,
    int maxBytes = 100 * 1024 * 1024,
  }) async {
    if (cancellation?._cancelled ?? false) {
      throw WalrusException('Download cancelled.');
    }
    late final http.Client httpClient;
    var tooLarge = false;
    httpClient = _factory(
      onDownload: (done, total) {
        if (done > maxBytes) {
          tooLarge = true;
          httpClient.close();
          return;
        }
        onProgress?.call(done, total);
      },
    );
    cancellation?._abort = httpClient.close;
    // 100 MB on a slow connection takes a while.
    final client = _client(httpClient, cacheMaxSize: 1, seconds: 30 * 60);
    try {
      final bytes = await client.getBlob(blobId);
      if (cancellation?._cancelled ?? false) {
        throw WalrusException('Download cancelled.');
      }
      if (bytes.length > maxBytes) {
        throw WalrusException('This file exceeds its expected download size.');
      }
      return bytes;
    } on WalrusApiError catch (e) {
      throw WalrusException(_friendly(e), code: e.code);
    } on http.ClientException {
      throw WalrusException(
        tooLarge
            ? 'This file exceeds its expected download size.'
            : 'The download was interrupted. Try again.',
      );
    } on WalrusException {
      rethrow;
    } catch (_) {
      throw WalrusException('The download was interrupted. Try again.');
    } finally {
      cancellation?._abort = null;
      await client.close();
      httpClient.close();
    }
  }

  /// Checks that a blob can still be read (Dartus `getBlobMetadata`, a HEAD
  /// request). Missing means the storage period ended or it was deleted.
  Future<BlobAvailability> availability(String blobId) async {
    try {
      await _reader.getBlobMetadata(blobId);
      return BlobAvailability.available;
    } on WalrusApiError catch (e) {
      // 404: gone (storage ended or deleted). 400: not a readable blob ID.
      return e.code == 404 || e.code == 400
          ? BlobAvailability.missing
          : BlobAvailability.unknown;
    } catch (_) {
      return BlobAvailability.unknown;
    }
  }

  static String _friendly(WalrusApiError e) {
    if (e.code == 404) {
      return 'This file is no longer stored on Walrus. Its storage period may have ended.';
    }
    if (e.message.isNotEmpty && !e.message.startsWith('HTTP ')) {
      return e.message;
    }
    return 'Walrus storage did not respond (${e.code}). Try again.';
  }

  Future<void> close() async {
    await _reader.close();
    _readerHttp.close();
  }
}
