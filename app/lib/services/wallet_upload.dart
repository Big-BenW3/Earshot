/// One file on its way to Walrus, paid for by the host's wallet, and then
/// listed on Earshot. Used for episodes and cover art.
library;

import 'dart:async';

import 'package:dartus/dartus.dart'
    show
        InsufficientWalBalanceError,
        WalrusTransactionOutcomeUnknown,
        WalletTransactionSigner,
        WalrusWriteStage;
import 'package:flutter/foundation.dart';
import 'package:sui_wallet_web/sui_wallet_web.dart';
import 'package:upload_recovery/walrus_recovery.dart';

import '../models/models.dart';
import 'api_client.dart';
import 'auth.dart';
import 'wallet_storage.dart';

/// Where an upload is. The four wallet steps follow Dartus's
/// [WalrusWriteStage]; [saving] is the claim on Earshot's server.
enum UploadPhase {
  ready,
  preparing,
  approvePayment,
  uploading,
  approveFinish,
  saving,
  done,
  failed,
}

enum UploadProblemKind {
  /// The wallet lacks WAL for storage.
  notEnoughWal,

  /// The wallet is connected to another account than the signed-in one.
  wrongAccount,

  /// No wallet is connected (it was locked or disconnected).
  noWallet,

  /// The person declined in the wallet. Not scary: try again.
  declined,

  /// The session ended; sign in again.
  signedOut,

  /// Anything else; "Try again" continues where it stopped.
  other,
}

class UploadProblem {
  const UploadProblem(this.kind, this.message);
  final UploadProblemKind kind;
  final String message;
}

class WalletUpload extends ChangeNotifier {
  WalletUpload({
    required this.bytes,
    required this.storage,
    required this.api,
    required this.auth,
    required this.epochs,
    this.claimRetryDelay = const Duration(seconds: 2),
    this.claimAttempts = 6,
    this.onDisposed,
    this.recovery,
  });

  final Uint8List bytes;
  final WalletStorage storage;
  final EarshotApi api;
  final AuthController auth;
  final int epochs;

  /// Sui's GraphQL (which the server reads) can trail the full node the
  /// wallet used by a few seconds, so a claim that finds nothing, or finds
  /// the blob not certified yet, is retried [claimAttempts] times, this far
  /// apart.
  final Duration claimRetryDelay;
  final int claimAttempts;
  final VoidCallback? onDisposed;
  final WalrusUploadRecovery? recovery;
  UploadRecoverySession? _recoverySession;
  Map<String, Object?> _recoveryMetadata = {};
  Future<void> releaseRecovery() async => _recoverySession?.release();

  void setRecoveryMetadata(Map<String, Object?> metadata) {
    _recoveryMetadata = Map.of(metadata);
  }

  bool _listed = false;
  bool get needsRetention => !_listed && (busy || _paid || _outcomeUnknown);
  Future<void> markListed() async {
    await _recoverySession?.complete();
    _set(() => _listed = true);
  }

  UploadPhase _phase = UploadPhase.ready;
  UploadPhase get phase => _phase;

  /// The last wallet step reached, so a failure can say where it stopped.
  UploadPhase? _reached;
  UploadPhase? get reached => _reached;

  StorageQuote? _quote;
  StorageQuote? get quote => _quote;
  bool _quoteFailed = false;
  bool get quoteFailed => _quoteFailed;

  int _sent = 0;
  int _total = 0;
  int get sent => _sent;
  int get total => _total == 0 ? bytes.length : _total;

  UploadProblem? _problem;
  UploadProblem? get problem => _problem;

  ClaimedBlob? _result;
  ClaimedBlob? get result => _result;

  /// True once the wallet has paid (registered), so a retry costs nothing
  /// more for storage.
  bool get paid => _paid;
  bool _paid = false;

  PendingWrite? _write;
  String? _objectId;
  bool _disposed = false;
  bool _running = false;
  bool _outcomeUnknown = false;
  String? _owner;
  bool get canReplace => !busy && !_paid && !_outcomeUnknown;

  bool get busy =>
      _running ||
      switch (_phase) {
        UploadPhase.preparing ||
        UploadPhase.approvePayment ||
        UploadPhase.uploading ||
        UploadPhase.approveFinish ||
        UploadPhase.saving => true,
        _ => false,
      };

  void _set(void Function() change) {
    change();
    if (!_disposed) notifyListeners();
  }

  /// Asks Walrus what storing these bytes costs. A failure only hides the
  /// figure; the wallet still shows the amount before approving.
  Future<void> loadQuote() async {
    try {
      final quote = await storage.estimate(size: bytes.length, epochs: epochs);
      _set(() => _quote = quote);
    } on Object catch (e) {
      debugPrint('Walrus estimate failed: $e');
      _set(() => _quoteFailed = true);
    }
  }

  /// Stores the file (or continues a failed attempt) and lists it on
  /// Earshot. Returns the listed blob, or null after a failure ([problem]).
  Future<ClaimedBlob?> start() async {
    if (_disposed || busy) return null;
    _running = true;
    notifyListeners();
    try {
      return await _start();
    } finally {
      _running = false;
      if (_result == null) await _recoverySession?.release();
      if (!_disposed) notifyListeners();
    }
  }

  Future<ClaimedBlob?> _start() async {
    final signedIn = auth.address;
    if (signedIn == null) {
      return _fail(
        UploadProblemKind.signedOut,
        'Your sign-in has ended. Sign in again to upload.',
      );
    }
    if (_owner != null && _owner != signedIn) {
      return _fail(
        UploadProblemKind.wrongAccount,
        'This upload belongs to ${shortenSuiAddress(_owner!)}. Sign in with that account to continue.',
      );
    }
    final account = auth.wallet.account;
    if (account == null) {
      return _fail(
        UploadProblemKind.noWallet,
        'Connect your wallet (${shortenSuiAddress(signedIn)}) to pay for '
        'storage.',
      );
    }
    if (account.address != signedIn) {
      return _fail(
        UploadProblemKind.wrongAccount,
        'Your wallet is on ${shortenSuiAddress(account.address)}, but you '
        'signed in as ${shortenSuiAddress(signedIn)}. Switch your wallet to '
        'that account, then try again.',
      );
    }

    if (_problem != null) _set(() => _problem = null);
    // Nothing is paid for a host whose session has ended.
    if (_objectId == null && !_paid && !await auth.confirmSession()) {
      return _fail(
        UploadProblemKind.signedOut,
        'Could not confirm your sign-in. Reconnect and try again.',
      );
    }
    if (_disposed) return null;
    try {
      final session = _recoverySession;
      if (session != null) {
        await session.activate();
        await session.updateMetadata(_recoveryMetadata);
      }
      if (_result != null) return _result;
      if (_objectId == null) {
        _owner ??= signedIn;
        final write = _write ??= storage.prepare(bytes, epochs: epochs);
        final coordinator = recovery;
        if (coordinator != null &&
            write is RecoveryCheckpointSource &&
            _recoverySession == null) {
          _recoverySession = await coordinator.bind(
            write as RecoveryCheckpointSource,
            owner: signedIn,
            metadata: _recoveryMetadata,
          );
        }
        final signer =
            coordinator?.signer(
              account.address,
              canContinue: () =>
                  !_disposed &&
                  auth.address == _owner &&
                  auth.wallet.account?.address == _owner,
            ) ??
            WalletTransactionSigner(
              address: account.address,
              isDefinitelyNotCommitted: (error) =>
                  error is SuiWalletException && error.definitelyNotSubmitted,
              execute: (tx) async {
                if (_disposed ||
                    auth.address != _owner ||
                    auth.wallet.account?.address != _owner) {
                  throw const SuiWalletException(
                    SuiWalletErrorKind.notConnected,
                    'Sign in with the upload account to continue.',
                    definitelyNotSubmitted: true,
                  );
                }
                return (await auth.wallet.signAndExecuteTransaction(
                  tx.json,
                )).digest;
              },
            );
        _objectId = await write.run(
          signer,
          onStage: (stage) => _set(() {
            _phase = switch (stage) {
              WalrusWriteStage.encoding => UploadPhase.preparing,
              WalrusWriteStage.registering => UploadPhase.approvePayment,
              WalrusWriteStage.uploading => UploadPhase.uploading,
              WalrusWriteStage.certifying => UploadPhase.approveFinish,
            };
            if (stage.index > WalrusWriteStage.registering.index) _paid = true;
            _reached = _phase;
          }),
          onProgress: (sent, total) => _set(() {
            _sent = sent;
            _total = total;
          }),
        );
        _paid = true;
      }
      _set(() => _phase = UploadPhase.saving);
      final claimed = await _claim(_objectId!);
      _set(() {
        _result = claimed;
        _phase = UploadPhase.done;
      });
      return claimed;
    } on InsufficientWalBalanceError {
      // Nothing was registered: start afresh once the wallet has WAL.
      if (_recoverySession == null) _write = null;
      return _fail(
        UploadProblemKind.notEnoughWal,
        'Your wallet needs a little WAL to pay for storage.',
      );
    } on WalrusTransactionOutcomeUnknown {
      _outcomeUnknown = true;
      return _fail(UploadProblemKind.other, walletSubmissionUnknownMessage);
    } on SuiWalletException catch (e) {
      return _fail(switch (e.kind) {
        SuiWalletErrorKind.rejected => UploadProblemKind.declined,
        SuiWalletErrorKind.notConnected ||
        SuiWalletErrorKind.locked => UploadProblemKind.noWallet,
        _ => UploadProblemKind.other,
      }, e.message);
    } on ApiException catch (e) {
      if (e.status == 401) {
        auth.sessionEnded();
        return _fail(
          UploadProblemKind.signedOut,
          'Your sign-in has ended. Sign in again, then try again to finish '
          'listing the file. It is already stored and paid for.',
        );
      }
      return _fail(UploadProblemKind.other, e.message);
    } on UploadRecoveryException catch (e) {
      return _fail(UploadProblemKind.other, e.message);
    } on Object catch (e) {
      return _fail(
        UploadProblemKind.other,
        'Storing the file stopped: ${_plain(e)}',
      );
    }
  }

  Future<ClaimedBlob> _claim(String objectId) async {
    for (var attempt = 1; ; attempt++) {
      try {
        return await api.claimBlob(objectId);
      } on ApiException catch (e) {
        final retry =
            e.status == 404 ||
            e.status == 502 ||
            e.offline ||
            e.code == 'BLOB_NOT_CERTIFIED';
        if (!retry || attempt >= claimAttempts) rethrow;
      }
      await Future<void>.delayed(claimRetryDelay);
    }
  }

  Null _fail(UploadProblemKind kind, String message) {
    _set(() {
      _problem = UploadProblem(kind, message);
      _phase = UploadPhase.failed;
    });
    return null;
  }

  static String _plain(Object e) {
    final text = '$e'.replaceFirst(
      RegExp(r'^[A-Za-z]*(Exception|Error): '),
      '',
    );
    return text.length > 200 ? '${text.substring(0, 197)}…' : text;
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_recoverySession?.release());
    onDisposed?.call();
    super.dispose();
  }
}
