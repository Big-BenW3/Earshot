import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import 'screens/admin_screen.dart';
import 'screens/create_show_screen.dart';
import 'screens/episode_screen.dart';
import 'screens/home_screen.dart';
import 'screens/show_screen.dart';
import 'services/playback/player_controller.dart';
import 'services/services.dart';
import 'theme/theme.dart';
import 'theme/tokens.dart';
import 'util/format.dart';
import 'widgets/common.dart';
import 'widgets/player_bar.dart';

GoRouter buildRouter({String initialLocation = '/app'}) => GoRouter(
  initialLocation: initialLocation,
  errorBuilder: (context, state) => const AppShell(
    child: PageFrame(children: [NotFoundState(title: 'Page not found')]),
  ),
  routes: [
    ShellRoute(
      builder: (context, state, child) => AppShell(child: child),
      routes: [
        // The marketing page owns "/" (served by the server); the app
        // home lives at /app.
        GoRoute(path: '/', redirect: (_, _) => '/app'),
        GoRoute(path: '/app', builder: (_, _) => const HomeScreen()),
        GoRoute(
          path: '/new',
          builder: (_, _) => const CreateShowScreen(),
          onExit: (context, _) =>
              context.services.confirmLeavingUploads(context),
        ),
        GoRoute(
          path: '/s/:slug',
          builder: (_, s) => ShowScreen(slug: s.pathParameters['slug']!),
          routes: [
            GoRoute(
              path: 'admin',
              onExit: (context, _) =>
                  context.services.confirmLeavingUploads(context),
              builder: (_, s) => AdminScreen(slug: s.pathParameters['slug']!),
            ),
            GoRoute(
              path: 'e/:id',
              builder: (_, s) => EpisodeScreen(
                slug: s.pathParameters['slug']!,
                episodeId: s.pathParameters['id']!,
                startAt: parseTimestamp(s.uri.queryParameters['t']),
              ),
            ),
          ],
        ),
      ],
    ),
  ],
);

class EarshotApp extends StatefulWidget {
  const EarshotApp({
    super.key,
    required this.services,
    this.initialLocation = '/',
  });

  final Services services;
  final String initialLocation;

  @override
  State<EarshotApp> createState() => _EarshotAppState();
}

class _EarshotAppState extends State<EarshotApp> {
  late final GoRouter _router = buildRouter(
    initialLocation: widget.initialLocation,
  );

  @override
  void initState() {
    super.initState();
    widget.services.browser.setBeforeUnloadGuard(
      () => widget.services.hasUnfinishedUploads,
    );
  }

  @override
  void dispose() {
    widget.services.browser.setBeforeUnloadGuard(null);
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ServicesScope(
      services: widget.services,
      child: MaterialApp.router(
        title: 'Earshot',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        darkTheme: buildTheme(),
        themeMode: ThemeMode.dark,
        routerConfig: _router,
      ),
    );
  }
}

/// Wraps every page: the warm background glow, keyboard shortcuts and the
/// persistent player bar.
///
/// Shortcuts: K (or Space when nothing else has focus) plays and pauses,
/// J and L skip back and forward 15 seconds.
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.child});
  final Widget child;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final _node = FocusNode(debugLabel: 'shell');

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  bool _editingText() {
    final focus = FocusManager.instance.primaryFocus?.context;
    if (focus == null) return false;
    return focus.widget is EditableText ||
        focus.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  KeyEventResult _onKey(PlayerController player, KeyEvent e) {
    if (e is! KeyDownEvent || !player.hasEpisode || _editingText()) {
      return KeyEventResult.ignored;
    }
    final k = e.logicalKey;
    final nothingFocused = FocusManager.instance.primaryFocus == _node;
    if (k == LogicalKeyboardKey.keyK ||
        (k == LogicalKeyboardKey.space && nothingFocused)) {
      player.toggle();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.keyJ) {
      player.skip(-skipStep);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.keyL) {
      player.skip(skipStep);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final player = context.services.player;
    return Focus(
      focusNode: _node,
      autofocus: true,
      onKeyEvent: (_, e) => _onKey(player, e),
      child: Scaffold(
        backgroundColor: Palette.walnut,
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(-0.6, -1.15),
              radius: 1.3,
              colors: [Color(0xFF3A2414), Palette.walnut],
              stops: [0, 0.7],
            ),
          ),
          child: Column(
            children: [
              Expanded(child: SafeArea(bottom: false, child: widget.child)),
              const PlayerBar(),
            ],
          ),
        ),
      ),
    );
  }
}
