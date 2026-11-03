import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:upload_recovery/walrus_recovery.dart';

import '../models/models.dart';
import 'api_client.dart';
import 'auth.dart';
import 'local_store.dart';
import 'platform/browser.dart';
import 'playback/player_controller.dart';
import 'wallet_storage.dart';
import 'wallet_upload.dart';
import 'walrus_service.dart';

/// Everything screens need, provided once above the router.
class Services {
  Services({
    required this.config,
    required this.api,
    required this.walrus,
    required this.browser,
    required this.store,
    required this.player,
    required this.auth,
    required this.storage,
    this.recovery,
    this.claimRetryDelay = const Duration(seconds: 2),
  });

  final AppConfig config;
  final EarshotApi api;
  final WalrusService walrus;
  final Browser browser;
  final LocalStore store;
  final PlayerController player;

  /// Host sign-in (Sui wallet). Listener pages never use it.
  final AuthController auth;

  /// Wallet-paid Walrus writes (Dartus `WalrusWriter`).
  final WalletStorage storage;
  final WalrusUploadRecovery? recovery;

  /// How long to wait before asking the server again for a blob the full
  /// node does not show yet.
  final Duration claimRetryDelay;

  /// A new wallet-paid upload of [bytes], for the app's suggested epochs.
  final _uploads = <WalletUpload>{};
  bool get hasUnfinishedUploads => _uploads.any((u) => u.needsRetention);

  Future<bool> confirmLeavingUploads(BuildContext context) async {
    if (!hasUnfinishedUploads) return true;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Leave this upload?'),
            content: Text(
              recovery == null
                  ? 'Stay here to finish your upload.'
                  : 'Your upload is saved in this browser. Return with the same wallet to continue. Unsaved form edits may be lost.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Stay here'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Leave anyway'),
              ),
            ],
          ),
        ) ??
        false;
  }

  WalletUpload newUpload(Uint8List bytes) {
    late final WalletUpload upload;
    upload = WalletUpload(
      bytes: bytes,
      storage: storage,
      api: api,
      auth: auth,
      recovery: recovery,
      epochs: config.epochs,
      claimRetryDelay: claimRetryDelay,
      onDisposed: () => _uploads.remove(upload),
    );
    _uploads.add(upload);
    return upload;
  }
}

class ServicesScope extends InheritedWidget {
  const ServicesScope({
    super.key,
    required this.services,
    required super.child,
  });

  final Services services;

  static Services of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ServicesScope>();
    assert(scope != null, 'ServicesScope missing');
    return scope!.services;
  }

  @override
  bool updateShouldNotify(ServicesScope oldWidget) =>
      services != oldWidget.services;
}

extension ServicesContext on BuildContext {
  Services get services => ServicesScope.of(this);
}
