import 'package:flutter/material.dart';
import 'package:sui_wallet_web/sui_wallet_web.dart' show shortenSuiAddress;

import '../services/auth.dart';
import '../services/services.dart';
import '../theme/tokens.dart';
import 'common.dart';
import 'press.dart';

/// Header control for hosts: "Sign in", or the signed-in address with a
/// Sign out menu. Listener pages never show it.
class AccountChip extends StatelessWidget {
  const AccountChip({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.services.auth;
    return ListenableBuilder(
      listenable: auth,
      builder: (context, _) {
        if (auth.checking) return const SizedBox(height: 44);
        final address = auth.address;
        if (address == null) {
          return Press(
            child: OutlinedButton.icon(
              onPressed: auth.busy ? null : () => signInWithFeedback(context),
              icon: const Icon(Icons.account_balance_wallet_outlined, size: 18),
              label: Text(auth.busy ? 'Signing in…' : 'Sign in'),
            ),
          );
        }
        return MenuAnchor(
          style: const MenuStyle(
            backgroundColor: WidgetStatePropertyAll(Palette.raised),
          ),
          menuChildren: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
              child: Semantics(
                label: 'Signed in as $address',
                child: ExcludeSemantics(
                  child: Text(
                    'Signed in as ${shortenSuiAddress(address)}',
                    style: TextStyles.small,
                  ),
                ),
              ),
            ),
            MenuItemButton(
              leadingIcon: const Icon(Icons.logout_rounded, size: 18),
              onPressed: () async {
                if (!await context.services.confirmLeavingUploads(context)) {
                  return;
                }
                try {
                  await auth.signOut();
                  if (context.mounted) showToast(context, 'Signed out');
                } catch (_) {
                  if (context.mounted) {
                    showToast(
                      context,
                      'Could not sign out. Check your connection and try again.',
                    );
                  }
                }
              },
              child: const Text('Sign out'),
            ),
          ],
          builder: (context, controller, _) => Semantics(
            button: true,
            label: 'Account ${shortenSuiAddress(address)}',
            excludeSemantics: true,
            child: Press(
              child: OutlinedButton.icon(
                onPressed: () =>
                    controller.isOpen ? controller.close() : controller.open(),
                icon: const Icon(
                  Icons.account_balance_wallet_outlined,
                  size: 18,
                ),
                label: Text(
                  shortenSuiAddress(address),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyles.timecode.copyWith(
                    color: Palette.cream,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Runs sign-in and shows any error as a toast.
Future<bool> signInWithFeedback(BuildContext context) async {
  final auth = context.services.auth;
  final error = await auth.signIn(context);
  if (!context.mounted) return false;
  if (error != null) {
    showToast(context, error);
    return false;
  }
  if (auth.signedIn) showToast(context, 'Signed in');
  return auth.signedIn;
}

/// The sign-in call to action for host-only pages.
class SignInPanel extends StatefulWidget {
  const SignInPanel({super.key, required this.title, required this.body});

  final String title;
  final String body;

  @override
  State<SignInPanel> createState() => _SignInPanelState();
}

class _SignInPanelState extends State<SignInPanel> {
  String? _error;

  Future<void> _signIn() async {
    setState(() => _error = null);
    final auth = context.services.auth;
    final error = await auth.signIn(context);
    if (mounted) setState(() => _error = error);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.services.auth;
    final compact = MediaQuery.sizeOf(context).width < 600;
    return ListenableBuilder(
      listenable: auth,
      builder: (context, _) => Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.xxxl),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Container(
              padding: EdgeInsets.all(compact ? Space.xl : Space.xxl),
              decoration: BoxDecoration(
                color: Palette.night,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Palette.line),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const EarshotMark(size: 48),
                  const SizedBox(height: Space.xl),
                  Semantics(
                    header: true,
                    child: Text(
                      widget.title,
                      style: TextStyles.headline(compact),
                    ),
                  ),
                  const SizedBox(height: Space.sm),
                  Text(widget.body, style: TextStyles.bodyMuted),
                  const SizedBox(height: Space.xl),
                  Press(
                    child: FilledButton.icon(
                      onPressed: auth.busy ? null : _signIn,
                      icon: auth.busy
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Palette.night,
                              ),
                            )
                          : const Icon(Icons.account_balance_wallet_outlined),
                      label: Text(
                        auth.busy
                            ? signInStepLabel(auth.step)
                            : 'Sign in with a Sui wallet',
                      ),
                    ),
                  ),
                  const SizedBox(height: Space.md),
                  const Text(
                    'Slush or any Wallet Standard wallet. Signing in does not send '
                    'a transaction or cost gas. Listeners never need a wallet.',
                    style: TextStyles.small,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: Space.md),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        _error!,
                        style: TextStyles.small.copyWith(color: Palette.tube),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shows [child] only to a signed-in host; otherwise a sign-in panel.
class SignedIn extends StatefulWidget {
  const SignedIn({
    super.key,
    required this.title,
    required this.body,
    required this.child,
  });
  final String title;
  final String body;
  final Widget child;

  @override
  State<SignedIn> createState() => _SignedInState();
}

class _SignedInState extends State<SignedIn> {
  String? _owner;

  @override
  Widget build(BuildContext context) {
    final services = context.services;
    final auth = services.auth;
    return ListenableBuilder(
      listenable: auth,
      builder: (context, _) {
        final address = auth.address;
        if (address == null && !services.hasUnfinishedUploads) _owner = null;
        final accountChanged =
            _owner != null && address != null && _owner != address;
        final keepUpload = accountChanged && services.hasUnfinishedUploads;
        if (address != null && !keepUpload) _owner = address;
        Widget? gate;
        if (auth.checking) {
          gate = const PageFrame(
            showFooter: false,
            headerTrailing: AccountChip(),
            children: [LoadingState(label: 'Checking your sign-in')],
          );
        } else if (!auth.signedIn || keepUpload) {
          gate = PageFrame(
            headerTrailing: const AccountChip(),
            children: [
              const SizedBox(height: Space.lg),
              const AuthNotice(),
              SignInPanel(
                title: keepUpload
                    ? 'Finish the upload with its original account'
                    : widget.title,
                body: keepUpload
                    ? 'Switch your wallet to ${shortenSuiAddress(_owner!)} and sign in to finish the upload.'
                    : widget.body,
              ),
              if (keepUpload)
                TextButton(
                  onPressed: () async {
                    if (!await services.confirmLeavingUploads(context) ||
                        !mounted) {
                      return;
                    }
                    setState(() => _owner = auth.address);
                  },
                  child: const Text('Discard unfinished upload'),
                ),
            ],
          );
        }
        return Stack(
          fit: StackFit.expand,
          children: [
            if (_owner != null)
              Offstage(
                offstage: gate != null,
                child: ExcludeFocus(
                  excluding: gate != null,
                  child: KeyedSubtree(
                    key: ValueKey(_owner),
                    child: widget.child,
                  ),
                ),
              ),
            ?gate,
          ],
        );
      },
    );
  }
}

/// A dismissible banner for auth notices (account switched, sign-in ended).
class AuthNotice extends StatelessWidget {
  const AuthNotice({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.services.auth;
    return ListenableBuilder(
      listenable: auth,
      builder: (context, _) {
        final notice = auth.notice;
        if (notice == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: Space.lg),
          child: Semantics(
            liveRegion: true,
            child: Container(
              padding: const EdgeInsets.fromLTRB(
                Space.lg,
                Space.sm,
                Space.xs,
                Space.sm,
              ),
              decoration: BoxDecoration(
                color: Palette.surface,
                borderRadius: BorderRadius.circular(Radii.card),
                border: Border.all(color: Palette.amber.withValues(alpha: 0.6)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    color: Palette.amber,
                    size: 20,
                  ),
                  const SizedBox(width: Space.md),
                  Expanded(child: Text(notice, style: TextStyles.small)),
                  IconButton(
                    tooltip: 'Dismiss',
                    onPressed: auth.clearNotice,
                    icon: const Icon(Icons.close_rounded, size: 18),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
