/// Storing files on Walrus, paid for by the host's own wallet.
///
/// [WalletStorage] is the small seam between the app and Dartus's
/// [WalrusWriter], so widget tests can swap in a fake that never touches the
/// network. The real one, [DartusWalletStorage], computes the blob ID with
/// `walrus-wasm` in a Web Worker, asks the wallet to register and pay, sends
/// the bytes to Mysten's upload relay through the app's XHR client (so the
/// upload reports progress) and asks the wallet to certify.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dartus/dartus.dart';
import 'package:http/http.dart' as http;
import 'package:upload_recovery/walrus_recovery.dart';

import 'platform/progress_client.dart';

/// What storing a file would cost, in WAL (gas comes on top).
class StorageQuote {
  const StorageQuote({required this.frost, required this.epochs});

  /// WAL for storage and registration, in FROST (10^-9 WAL).
  final BigInt frost;
  final int epochs;

  /// "0.0011", "0.25", "3.1": short, but never rounded down to zero.
  String get walText {
    final wal = frost / BigInt.from(1000000000);
    if (wal <= 0) return '0';
    if (wal < 0.000001) return 'under 0.000001';
    // Two decimals from 1 WAL up, otherwise two significant digits; never
    // exponent notation or trailing zeros.
    final text = wal >= 1
        ? wal.toStringAsFixed(2)
        : double.parse(
            wal.toStringAsPrecision(2),
          ).toStringAsFixed((-_log10(wal)).ceil() + 1);
    return text
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  String get epochsText => epochs == 1 ? '1 epoch' : '$epochs epochs';

  static double _log10(double x) => math.log(x) / math.ln10;
}

/// One file being stored. Keep it after a failure: [run] continues where it
/// stopped, so a declined approval never registers or pays twice.
abstract interface class PendingWrite {
  /// Performs the remaining steps with [signer] and returns the Blob
  /// object ID, once certified.
  Future<String> run(
    WalrusTransactionSigner signer, {
    void Function(WalrusWriteStage stage)? onStage,
    ProgressCallback? onProgress,
  });
}

abstract interface class WalletStorage {
  Future<StorageQuote> estimate({required int size, required int epochs});

  /// Starts a write of [bytes] for [epochs] epochs (nothing happens until
  /// [PendingWrite.run]).
  PendingWrite prepare(Uint8List bytes, {required int epochs});

  void close();
}

/// [WalletStorage] over Dartus's [WalrusWriter].
class DartusWalletStorage implements WalletStorage {
  DartusWalletStorage({required WalrusNetwork network, http.Client? client}) {
    // One writer for the app (one Web Worker for walrus-wasm). Uploads run
    // one at a time, so progress goes to whichever write is running.
    _http =
        client ??
        createProgressClient(
          onUpload: (sent, total) => _progress?.call(sent, total),
        );
    _writer = WalrusWriter(network: network, httpClient: _http);
  }

  /// `sui:testnet` → testnet, `sui:mainnet` → mainnet.
  static WalrusNetwork networkFor(String suiChain) =>
      suiChain.endsWith('mainnet')
      ? WalrusNetwork.mainnet
      : WalrusNetwork.testnet;

  late final http.Client _http;
  late final WalrusWriter _writer;
  ProgressCallback? _progress;
  bool _running = false;

  @override
  Future<StorageQuote> estimate({
    required int size,
    required int epochs,
  }) async {
    final estimate = await _writer.estimate(size: size, epochs: epochs);
    return StorageQuote(frost: estimate.cost.total, epochs: epochs);
  }

  @override
  PendingWrite prepare(Uint8List bytes, {required int epochs}) =>
      _DartusWrite(this, bytes, epochs);

  @override
  void close() {
    _writer.close();
    _http.close();
  }
}

class _DartusWrite implements PendingWrite, RecoveryCheckpointSource {
  _DartusWrite(this._storage, Uint8List bytes, int epochs) {
    _flow = _storage._writer.writeFlow(
      bytes,
      epochs: epochs,
      onCheckpoint: (checkpoint) async => _onCheckpoint?.call(checkpoint),
    );
  }

  CheckpointHandler? _onCheckpoint;
  @override
  set onCheckpoint(CheckpointHandler? handler) => _onCheckpoint = handler;
  @override
  WalrusWriteCheckpoint get checkpoint => _flow.checkpoint;

  final DartusWalletStorage _storage;
  late final WalrusWriteFlow _flow;

  @override
  Future<String> run(
    WalrusTransactionSigner signer, {
    void Function(WalrusWriteStage stage)? onStage,
    ProgressCallback? onProgress,
  }) async {
    if (_storage._running) {
      throw StateError(
        'Another upload is still running. Wait for it to finish.',
      );
    }
    _storage._running = true;
    _storage._progress = onProgress;
    try {
      final result = await _flow.run(signer, onStage: onStage);
      return result.blobObjectId;
    } finally {
      _storage._progress = null;
      _storage._running = false;
    }
  }
}
