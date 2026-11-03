import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'app.dart';
import 'package:sui_wallet_web/sui_wallet_web.dart';

import 'services/api_client.dart';
import 'services/auth.dart';
import 'services/local_store.dart';
import 'services/platform/browser.dart';
import 'services/playback/audio_engine.dart';
import 'services/playback/player_controller.dart';
import 'services/services.dart';
import 'services/wallet_storage.dart';
import 'services/walrus_service.dart';
import 'services/upload_recovery.dart';
import 'theme/theme.dart';
import 'theme/tokens.dart';
import 'widgets/common.dart';

void main() {
  usePathUrlStrategy();
  WidgetsFlutterBinding.ensureInitialized();
  // Keep the accessibility tree on so screen readers and keyboard users get
  // labelled controls without an extra click.
  SemanticsBinding.instance.ensureSemantics();
  // Read the deep link before anything can change the address bar.
  final browser = createBrowser();
  final initial = WidgetsBinding.instance.platformDispatcher.defaultRouteName;
  runApp(Bootstrap(browser: browser, initialLocation: initial));
}

/// Loads server config (aggregator URL, limits), then starts the app.
class Bootstrap extends StatefulWidget {
  const Bootstrap({
    super.key,
    required this.browser,
    required this.initialLocation,
  });

  final Browser browser;
  final String initialLocation;

  @override
  State<Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<Bootstrap> {
  Services? _services;
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    setState(() => _error = null);
    final origin = Uri.base.replace(path: '/', query: null, fragment: null);
    final api = EarshotApi(base: origin);
    try {
      final config = await api.config();
      final browser = widget.browser;
      final store = LocalStore(browser);
      final wallet = SuiWalletController(chain: config.suiChain);
      final auth = AuthController(
        wallet: wallet,
        client: SuiSignInClient(
          wallet: wallet,
          authBase: origin.resolve('/api/auth/'),
        ),
      );
      unawaited(auth.start());
      setState(() {
        _services = Services(
          config: config,
          api: api,
          walrus: WalrusService(aggregatorBase: config.aggregatorUrl),
          // The same network the wallet signs for (SUI_CHAIN on the server).
          storage: DartusWalletStorage(
            network: DartusWalletStorage.networkFor(config.suiChain),
          ),
          browser: browser,
          store: store,
          player: PlayerController(engine: createAudioEngine(), store: store),
          auth: auth,
          recovery: createUploadRecovery(
            api: api,
            wallet: wallet,
            chain: config.suiChain,
          ),
        );
      });
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = _services;
    if (services != null) {
      return EarshotApp(
        services: services,
        initialLocation: widget.initialLocation.isEmpty
            ? '/'
            : widget.initialLocation,
      );
    }
    // No MaterialApp here: a Navigator would rewrite the address bar to "/"
    // before the router reads the real deep link.
    return MediaQuery.fromView(
      view: View.of(context),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Theme(
          data: buildTheme(),
          child: Material(
            color: Palette.walnut,
            child: Center(
              child: _error == null
                  ? const DialLoader(label: 'Starting Earshot')
                  : Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.portable_wifi_off_rounded,
                            color: Palette.tube,
                            size: 40,
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Earshot could not start',
                            style: TextStyles.title,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _error!,
                            style: TextStyles.bodyMuted,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 24),
                          FilledButton(
                            onPressed: _start,
                            child: const Text('Try again'),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
