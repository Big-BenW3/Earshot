/// `POST /api/blobs`: a host lists a blob they stored with their own wallet.
///
/// The browser stores audio and cover art on Walrus itself (Dartus's
/// `WalrusWriter`: the host's wallet pays for storage and owns the Blob
/// object), then posts only the Blob object ID here. Nothing the browser
/// says is trusted. [WalrusBlobChecker] reads the object on Sui and checks
/// that it is a certified Walrus blob owned by the signed-in address; the
/// size, blob ID and storage epochs come from the chain, and the type comes
/// from the blob's first bytes on the aggregator. Episodes and the RSS feed
/// only ever use these records.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:sui_auth/sui_auth.dart' show SuiAuthRequest;
import 'package:walrus_blob_check/walrus_blob_check.dart';

import 'config.dart';
import 'sniff.dart';
import 'store.dart';

/// Claim errors use the sign-in error shape, which the app already reads:
/// `{"error": {"code": 409, "status": "ALREADY_CLAIMED", "message": "…"}}`.
Response claimError(
  int code,
  String status,
  String message, {
  Map<String, String>? headers,
}) => Response(
  code,
  body: jsonEncode({
    'error': {'code': code, 'status': status, 'message': message},
  }),
  headers: {
    'content-type': 'application/json; charset=utf-8',
    'cache-control': 'no-store',
    ...?headers,
  },
);

class BlobClaims {
  BlobClaims({
    required this.config,
    required this.store,
    required this.checker,
    DateTime Function()? clock,
  }) : _perAddress = RateLimiter(
         limit: config.claimsPerWindow,
         window: config.claimWindow,
         clock: clock,
       ),
       // Several hosts can share one network (a church office, a campus),
       // so a client IP gets more room than one address.
       _perClient = RateLimiter(
         limit: config.claimsPerWindow * 4,
         window: config.claimWindow,
         clock: clock,
       );

  final Config config;
  final Store store;
  final WalrusBlobChecker checker;
  final RateLimiter _perAddress;
  final RateLimiter _perClient;

  static final _objectId = RegExp(r'^0x[0-9a-fA-F]{1,64}$');

  String _limitText(int bytes) => '${(bytes / (1024 * 1024)).round()} MB';

  Future<Response> handle(Request request) async {
    if (request.method != 'POST') {
      return claimError(405, 'METHOD_NOT_ALLOWED', 'Use POST.');
    }
    final owner = request.suiAddress;
    if (owner == null) {
      return claimError(
        401,
        'NOT_SIGNED_IN',
        'Sign in with your Sui wallet to add files.',
      );
    }

    final Object? body;
    try {
      if ((request.contentLength ?? 0) > 4096) {
        return claimError(413, 'TOO_LARGE', 'The request is too large.');
      }
      final bytes = <int>[];
      await for (final chunk in request.read().timeout(
        const Duration(seconds: 30),
      )) {
        if (bytes.length + chunk.length > 4096) {
          return claimError(413, 'TOO_LARGE', 'The request is too large.');
        }
        bytes.addAll(chunk);
      }
      body = jsonDecode(utf8.decode(bytes));
    } on TimeoutException {
      return claimError(
        408,
        'REQUEST_TIMEOUT',
        'The request took too long. Try again.',
      );
    } on FormatException {
      return claimError(
        400,
        'BAD_REQUEST',
        'Send JSON: {"objectId": "0x..."}.',
      );
    }
    final raw = body is Map ? body['objectId'] : null;
    if (raw is! String || !_objectId.hasMatch(raw)) {
      return claimError(
        400,
        'BAD_REQUEST',
        'objectId must be a Sui object ID.',
      );
    }
    final objectId = normalizeSuiAddress(raw);
    final repeated = _repeated(objectId, owner);
    if (repeated != null) return repeated;

    // Every claim, good or bad, makes the server read Sui and the
    // aggregator, so the limit counts attempts per address and per client.
    final wait =
        _perAddress.take(owner) ?? _perClient.take(_clientKey(request));
    if (wait != null) {
      return claimError(
        429,
        'TOO_MANY_CLAIMS',
        'Too many uploads in a short time. Wait a few minutes and try again.',
        headers: {'retry-after': '${wait.inSeconds + 1}'},
      );
    }

    final StoredBlob blob;
    try {
      blob = await checker.check(objectId, owner: owner);
    } on BlobCheckException catch (e) {
      return _checkProblem(e);
    }

    // Size from the chain. The type is unknown yet, so the larger limit
    // first; covers get theirs once the bytes say it is an image.
    if (blob.size > config.maxAudioBytes) {
      return claimError(
        413,
        'FILE_TOO_LARGE',
        'Files can be up to ${_limitText(config.maxAudioBytes)}.',
      );
    }
    if (blob.size == 0) {
      return claimError(415, 'UNSUPPORTED_MEDIA_TYPE', 'The file is empty.');
    }

    final SniffResult? type;
    try {
      type = sniff(await checker.readStart(blob.blobId, length: sniffLength));
    } on BlobCheckException catch (e) {
      return _checkProblem(e);
    }
    if (type == null) {
      return claimError(
        415,
        'UNSUPPORTED_MEDIA_TYPE',
        'Upload MP3, M4A, AAC, OGG or WAV audio, or a PNG, JPEG or WebP '
            'cover image.',
      );
    }
    if (type.kind == UploadKind.image && blob.size > maxImageBytes) {
      return claimError(
        413,
        'FILE_TOO_LARGE',
        'Cover images can be up to ${_limitText(maxImageBytes)}.',
      );
    }

    final record = UploadRecord(
      objectId: blob.objectId,
      blobId: blob.blobId,
      ownerAddress: owner,
      kind: type.kind,
      mime: type.mime,
      sizeBytes: blob.size,
      startEpoch: blob.startEpoch,
      endEpoch: blob.endEpoch,
    );
    // Two claims of one object racing past the first check: one wins.
    if (!store.recordUpload(record)) {
      return _repeated(objectId, owner) ?? _alreadyClaimed();
    }
    return _recordResponse(record);
  }

  Response? _repeated(String objectId, String owner) {
    final record = store.uploadByObject(objectId);
    if (record == null) return null;
    return record.ownerAddress == owner
        ? _recordResponse(record)
        : _alreadyClaimed();
  }

  Response _recordResponse(UploadRecord record) => Response(
    201,
    body: jsonEncode(record.toJson()),
    headers: {
      'content-type': 'application/json; charset=utf-8',
      'cache-control': 'no-store',
    },
  );

  Response _alreadyClaimed() =>
      claimError(409, 'ALREADY_CLAIMED', 'That file is already on Earshot.');

  Response _checkProblem(BlobCheckException e) => switch (e.problem) {
    // A full node can trail the wallet by a moment; the app retries.
    BlobCheckProblem.notFound => claimError(
      404,
      'BLOB_NOT_FOUND',
      'Walrus does not show this file yet. Try again in a moment.',
    ),
    BlobCheckProblem.notCertified => claimError(
      409,
      'BLOB_NOT_CERTIFIED',
      'This file was paid for but not finished on Walrus. Try again to '
          'finish it.',
    ),
    BlobCheckProblem.expired => claimError(
      410,
      'BLOB_EXPIRED',
      'This file’s storage period has ended. Store it again before adding it.',
    ),
    BlobCheckProblem.wrongOwner => claimError(
      403,
      'NOT_YOUR_BLOB',
      'This file belongs to another Sui address. Upload it from the wallet '
          'you signed in with.',
    ),
    BlobCheckProblem.notWalrusBlob => claimError(
      403,
      'NOT_WALRUS_BLOB',
      'That is not a Walrus file.',
    ),
    BlobCheckProblem.unavailable => claimError(
      502,
      'SUI_UNAVAILABLE',
      'Could not check the file on Sui. Try again.',
    ),
  };

  String _clientKey(Request request) {
    if (config.trustProxy) {
      final forwarded = request.headers['x-forwarded-for'];
      if (forwarded != null && forwarded.trim().isNotEmpty) {
        return forwarded.split(',').first.trim();
      }
    }
    final info = request.context['shelf.io.connection_info'];
    return info is HttpConnectionInfo ? info.remoteAddress.address : 'local';
  }
}

/// A sliding-window counter per key: at most [limit] events per [window].
class RateLimiter {
  RateLimiter({
    required this.limit,
    required this.window,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final int limit;
  final Duration window;
  final DateTime Function() _clock;
  final _events = <String, List<DateTime>>{};

  /// Records an event for [key]. Returns null when allowed, otherwise how
  /// long until the oldest event in the window expires (nothing recorded).
  Duration? take(String key) {
    final now = _clock();
    final cutoff = now.subtract(window);
    if (_events.length > 10000) {
      _events.removeWhere((_, times) => times.last.isBefore(cutoff));
    }
    final times = _events.putIfAbsent(key, () => <DateTime>[])
      ..removeWhere((t) => !t.isAfter(cutoff));
    if (times.length >= limit) return times.first.difference(cutoff);
    times.add(now);
    return null;
  }
}
