import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sui_wallet_web/sui_wallet_web.dart';

/// Hosts sign in with a Sui wallet (shared `sui_wallet_web` package). The
/// server keeps the session in an HttpOnly `earshot_session` cookie;
/// listeners never need any of this.
class AuthController extends ChangeNotifier {
  AuthController({required this.wallet, required this.client});

  final SuiWalletController wallet;
  final SuiSignInClient client;
  StreamSubscription<SuiWalletChange>? _changes;

  SuiSessionInfo? _session;
  bool _checking = true;
  bool _busy = false;
  bool _disposed = false;
  int _revision = 0;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  SuiSignInStep? _step;
  String? _notice;

  SuiSessionInfo? get session => _session;
  String? get address => _session?.address;
  bool get signedIn => _session != null;

  /// True until the first session check returns.
  bool get checking => _checking;
  bool get busy => _busy;
  SuiSignInStep? get step => _step;

  /// A one-off message, e.g. the wallet switched accounts.
  String? get notice => _notice;

  /// Restores the wallet silently and asks the server who is signed in.
  Future<void> start() async {
    if (_disposed || _changes != null) return;
    _changes = wallet.changes.listen((change) {
      final s = _session;
      if (change.type == SuiWalletChangeType.accountChanged &&
          s != null &&
          change.state.account?.address != s.address) {
        final next = change.state.account?.address;
        _notice = next == null
            ? 'Your wallet disconnected. You are still signed in as '
                  '${s.shortAddress}.'
            : 'Your wallet switched to ${shortenSuiAddress(next)}. Sign in '
                  "again to manage that account's shows.";
        _notify();
      }
    });
    unawaited(wallet.init().catchError((Object _) {}));
    await refresh();
  }

  /// Re-reads the session from the server (null when signed out).
  Future<void> refresh() async {
    final revision = ++_revision;
    SuiSessionInfo? session;
    try {
      session = await client.currentSession();
    } on SuiSignInException {
      // Session state remains unknown until a later successful request.
    }
    if (_disposed || revision != _revision) return;
    _session = session;
    _checking = false;
    _notify();
  }

  /// Opens the wallet picker if needed, then signs in. Returns an error
  /// message to show, or null (signed in, or the person closed the picker).
  Future<String?> signIn(BuildContext context) async {
    if (_busy || _disposed) return null;
    _busy = true;
    final revision = ++_revision;
    _notice = null;
    _notify();
    try {
      if (!wallet.isConnected) {
        final account = await showSuiWalletPicker(
          context,
          controller: wallet,
          strings: const SuiWalletPickerStrings(
            title: 'Sign in to manage your shows',
          ),
        );
        if (account == null || _disposed || revision != _revision) return null;
      }
      final session = await client.signIn(
        onProgress: (step, {message}) {
          _step = step;
          _notify();
        },
      );
      if (!_disposed && revision == _revision) _session = session;
      return null;
    } on SuiSignInException catch (e) {
      return e.message;
    } finally {
      _busy = false;
      _step = null;
      _notify();
    }
  }

  /// Connects the wallet again (it was locked or disconnected) so it can
  /// pay for an upload. Returns the connected address, or null.
  Future<String?> connectWallet(BuildContext context) async {
    if (wallet.isConnected) return wallet.account?.address;
    final account = await showSuiWalletPicker(
      context,
      controller: wallet,
      strings: const SuiWalletPickerStrings(
        title: 'Connect the wallet that pays for storage',
      ),
    );
    _notify();
    return account?.address;
  }

  Future<void> signOut() async {
    ++_revision;
    await client.signOut();
    if (_disposed) return;
    _session = null;
    _notice = null;
    _notify();
  }

  /// Confirms the same account still owns the server session before payment.
  Future<bool> confirmSession() async {
    final expected = address;
    final revision = _revision;
    if (expected == null || _disposed) return false;
    try {
      final actual = await client.currentSession();
      if (_disposed || revision != _revision) return false;
      if (actual?.address == expected) return true;
      ++_revision;
      _session = actual;
      _notice = actual == null
          ? 'Your sign-in has ended. Sign in again to continue.'
          : 'Your signed-in account changed. Open its shows before uploading.';
      _notify();
    } on SuiSignInException {
      return false;
    }
    return false;
  }

  /// The server answered 401 (session ended elsewhere): forget it locally.
  void sessionEnded() {
    if (_session == null) return;
    ++_revision;
    _session = null;
    _notice = 'Your sign-in has ended. Sign in again to continue.';
    _notify();
  }

  void clearNotice() {
    _notice = null;
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_revision;
    _changes?.cancel();
    wallet.dispose();
    super.dispose();
  }
}

/// "Approve in your wallet" and friends, for the sign-in button.
String signInStepLabel(SuiSignInStep? step) => switch (step) {
  SuiSignInStep.connecting => 'Connecting to your wallet…',
  SuiSignInStep.requestingChallenge => 'Preparing sign-in…',
  SuiSignInStep.signing => 'Approve the message in your wallet…',
  SuiSignInStep.verifying => 'Checking your signature…',
  SuiSignInStep.done => 'Signed in',
  null => 'Signing in…',
};
