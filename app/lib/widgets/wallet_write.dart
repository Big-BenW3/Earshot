/// The wallet-paid upload, on screen: the cost before the first approval,
/// the four steps as dial lamps (prepare, pay, upload, finish), upload
/// progress, and every failure with a way forward.
library;

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/services.dart';
import '../services/wallet_upload.dart';
import '../theme/tokens.dart';
import '../util/format.dart';
import 'account.dart';
import 'press.dart';

/// Shows a [WalletUpload] in whatever phase it is: the cost card while
/// ready, the steps while working, the problem after a failure (with
/// [onRetry], which continues where it stopped).
class WalletWritePanel extends StatelessWidget {
  const WalletWritePanel({
    super.key,
    required this.upload,
    required this.onRetry,
    this.what = 'this file',
  });

  final WalletUpload upload;
  final VoidCallback onRetry;

  /// "this recording", "the cover art": used in the cost line.
  final String what;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: upload,
      builder: (context, _) => switch (upload.phase) {
        UploadPhase.ready => _CostCard(upload: upload, what: what),
        UploadPhase.done => const SizedBox.shrink(),
        UploadPhase.failed => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (upload.reached != null) ...[
              _Lamps(upload: upload),
              const SizedBox(height: Space.lg),
            ],
            _Problem(upload: upload, onRetry: onRetry),
          ],
        ),
        _ => _Working(upload: upload),
      },
    );
  }
}

/// "About 0.0011 WAL for 26 epochs, plus gas", before anything is asked.
class _CostCard extends StatelessWidget {
  const _CostCard({required this.upload, required this.what});
  final WalletUpload upload;
  final String what;

  @override
  Widget build(BuildContext context) {
    final quote = upload.quote;
    final cost = quote != null
        ? 'About ${quote.walText} WAL to store $what for '
              '${quote.epochsText}, plus a little SUI for gas and the upload relay fee.'
        : upload.quoteFailed
        ? 'Your wallet shows the cost before you approve.'
        : 'Working out the cost…';
    return Semantics(
      container: true,
      identifier: 'wallet-cost',
      child: Container(
        padding: const EdgeInsets.all(Space.lg),
        decoration: BoxDecoration(
          color: Palette.surface,
          borderRadius: BorderRadius.circular(Radii.card),
          border: Border.all(color: Palette.line),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Palette.amber.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.account_balance_wallet_outlined,
                color: Palette.amber,
                size: 20,
              ),
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('YOUR WALLET PAYS', style: TextStyles.overline),
                  const SizedBox(height: Space.xs),
                  Text(cost, style: TextStyles.body),
                  const SizedBox(height: Space.xs),
                  const Text(
                    'You approve twice: once to pay, once to finish. The file '
                    'belongs to your Sui address.',
                    style: TextStyles.small,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const _steps = [
  (UploadPhase.preparing, 'Prepare'),
  (UploadPhase.approvePayment, 'Pay'),
  (UploadPhase.uploading, 'Upload'),
  (UploadPhase.approveFinish, 'Finish'),
];

/// Four lamps on a dial strip. Done lamps glow moss, the current one amber.
class _Lamps extends StatelessWidget {
  const _Lamps({required this.upload});
  final WalletUpload upload;

  @override
  Widget build(BuildContext context) {
    final failed = upload.phase == UploadPhase.failed;
    // A decline stops the dial in amber: nothing is wrong, it waits.
    final stopTone = upload.problem?.kind == UploadProblemKind.declined
        ? Palette.amber
        : Palette.tube;
    final current = failed ? upload.reached : upload.phase;
    final at = current == UploadPhase.saving
        ? _steps.length
        : _steps.indexWhere((s) => s.$1 == current);
    return ExcludeSemantics(
      child: Row(
        children: [
          for (var i = 0; i < _steps.length; i++) ...[
            Expanded(
              child: Column(
                children: [
                  _Lamp(
                    state: i < at
                        ? _LampState.done
                        : i == at
                        ? (failed ? _LampState.stopped : _LampState.on)
                        : _LampState.off,
                    stopTone: stopTone,
                  ),
                  const SizedBox(height: Space.sm),
                  Text(
                    _steps[i].$2.toUpperCase(),
                    style: TextStyles.overline.copyWith(
                      color: i == at
                          ? (failed ? stopTone : Palette.amber)
                          : i < at
                          ? Palette.muted
                          : Palette.faint,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

enum _LampState { off, on, done, stopped }

class _Lamp extends StatelessWidget {
  const _Lamp({required this.state, required this.stopTone});
  final _LampState state;
  final Color stopTone;

  @override
  Widget build(BuildContext context) {
    final color = switch (state) {
      _LampState.off => Palette.night,
      _LampState.on => Palette.amber,
      _LampState.done => Palette.moss,
      _LampState.stopped => stopTone,
    };
    return AnimatedContainer(
      duration: Motion.enter,
      curve: Motion.out,
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
          color: state == _LampState.off ? Palette.faint : color,
          width: 1.5,
        ),
        boxShadow: state == _LampState.on
            ? [
                BoxShadow(
                  color: Palette.amber.withValues(alpha: 0.55),
                  blurRadius: 12,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
    );
  }
}

class _Working extends StatelessWidget {
  const _Working({required this.upload});
  final WalletUpload upload;

  @override
  Widget build(BuildContext context) {
    final quote = upload.quote;
    final total = upload.total;
    final fraction = total == 0 ? 0.0 : (upload.sent / total).clamp(0.0, 1.0);
    // The browser has sent every byte; the relay is still answering.
    final sentAll = total > 0 && upload.sent >= total;
    final (title, detail) = switch (upload.phase) {
      UploadPhase.preparing => (
        'Preparing…',
        'Working out the file’s Walrus ID. Long recordings take a few seconds.',
      ),
      UploadPhase.approvePayment => (
        'Approve the payment in your wallet',
        quote == null
            ? 'This registers the file on Walrus and pays for its storage.'
            : 'About ${quote.walText} WAL for ${quote.epochsText}, plus SUI gas and the upload relay fee.',
      ),
      UploadPhase.uploading when sentAll => (
        'Uploaded ${fileSize(total)}',
        'Walrus is storing it on its nodes. Keep this tab open.',
      ),
      UploadPhase.uploading => (
        'Uploading ${fileSize(upload.sent)} of ${fileSize(total)}  ·  '
            '${(fraction * 100).round()}%',
        'Sending the file to Walrus. Keep this tab open.',
      ),
      UploadPhase.approveFinish => (
        'Approve once more to finish',
        'This certifies the file on Walrus. It costs only gas, no more WAL.',
      ),
      _ => (
        'Listing it on Earshot…',
        'Checking the file on Sui. This takes a moment.',
      ),
    };
    final waitingOnWallet =
        upload.phase == UploadPhase.approvePayment ||
        upload.phase == UploadPhase.approveFinish;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Lamps(upload: upload),
        const SizedBox(height: Space.lg),
        Semantics(
          liveRegion: true,
          identifier: 'wallet-status',
          label: title,
          child: Container(
            padding: const EdgeInsets.all(Space.lg),
            decoration: BoxDecoration(
              color: Palette.surface,
              borderRadius: BorderRadius.circular(Radii.card),
              border: Border.all(
                color: waitingOnWallet
                    ? Palette.amber.withValues(alpha: 0.7)
                    : Palette.line,
              ),
            ),
            child: ExcludeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        waitingOnWallet
                            ? Icons.account_balance_wallet_outlined
                            : Icons.graphic_eq_rounded,
                        color: Palette.amber,
                        size: 20,
                      ),
                      const SizedBox(width: Space.md),
                      Expanded(
                        child: Text(
                          title,
                          style: upload.phase == UploadPhase.uploading
                              ? TextStyles.timecode.copyWith(
                                  color: Palette.cream,
                                  fontSize: 14,
                                )
                              : TextStyles.label,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Space.md),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: upload.phase == UploadPhase.uploading && !sentAll
                          ? fraction
                          : null,
                      minHeight: 6,
                    ),
                  ),
                  const SizedBox(height: Space.sm),
                  Text(detail, style: TextStyles.small),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Problem extends StatelessWidget {
  const _Problem({required this.upload, required this.onRetry});
  final WalletUpload upload;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: context.services.auth,
    builder: (context, _) => _content(context),
  );

  Widget _content(BuildContext context) {
    final services = context.services;
    final problem = upload.problem!;
    final declined = problem.kind == UploadProblemKind.declined;
    final (title, help) = switch (problem.kind) {
      UploadProblemKind.declined => (
        'You declined in your wallet',
        upload.paid
            ? 'Storage is already paid for. Try again to finish; you will not '
                  'pay twice.'
            : 'Nothing was charged. Try again when you are ready.',
      ),
      UploadProblemKind.notEnoughWal => (
        problem.message,
        'Get a little WAL in your wallet first: Slush can swap SUI for WAL. '
            'Then try again.',
      ),
      UploadProblemKind.wrongAccount => (
        'Wrong wallet account',
        problem.message,
      ),
      UploadProblemKind.noWallet => (
        'Your wallet is not connected',
        problem.message,
      ),
      UploadProblemKind.signedOut => (
        services.auth.signedIn ? 'Ready to continue' : 'Sign in again',
        problem.message,
      ),
      UploadProblemKind.other => (
        'The upload stopped',
        '${problem.message}${upload.paid ? ' Storage is already paid for; trying again continues from there.' : ''}',
      ),
    };
    final tone = declined ? Palette.amber : Palette.tube;
    final action = switch (problem.kind) {
      UploadProblemKind.noWallet => (
        'Connect wallet',
        Icons.account_balance_wallet_outlined,
        () async {
          final address = await services.auth.connectWallet(context);
          if (address != null) onRetry();
        },
      ),
      UploadProblemKind.signedOut when services.auth.signedIn => (
        'Try again',
        Icons.refresh_rounded,
        () async => onRetry(),
      ),
      UploadProblemKind.signedOut => (
        'Sign in again',
        Icons.login_rounded,
        () async {
          if (await signInWithFeedback(context)) onRetry();
        },
      ),
      _ => ('Try again', Icons.refresh_rounded, () async => onRetry()),
    };
    return Semantics(
      liveRegion: true,
      container: true,
      identifier: 'wallet-problem',
      child: Container(
        padding: const EdgeInsets.all(Space.lg),
        decoration: BoxDecoration(
          color: Palette.surface,
          borderRadius: BorderRadius.circular(Radii.card),
          border: Border.all(color: tone.withValues(alpha: 0.7)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  declined
                      ? Icons.pan_tool_alt_outlined
                      : Icons.error_outline_rounded,
                  color: tone,
                  size: 20,
                ),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: TextStyles.label),
                      const SizedBox(height: Space.xs),
                      Text(help, style: TextStyles.small),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: Space.lg),
            Press(
              child: FilledButton.icon(
                onPressed: action.$3,
                icon: Icon(action.$2),
                label: Text(action.$1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Stores a cover image with the host's wallet, in a dialog. Returns the
/// listed blob, or null when the host closes it. Pass the same [upload]
/// again after a failure to continue without paying twice.
Future<ClaimedBlob?> storeWithWallet(
  BuildContext context, {
  required WalletUpload upload,
  required String title,
  required String what,
}) => showDialog<ClaimedBlob>(
  context: context,
  barrierDismissible: false,
  builder: (context) => _StoreDialog(upload: upload, title: title, what: what),
);

class _StoreDialog extends StatefulWidget {
  const _StoreDialog({
    required this.upload,
    required this.title,
    required this.what,
  });
  final WalletUpload upload;
  final String title;
  final String what;

  @override
  State<_StoreDialog> createState() => _StoreDialogState();
}

class _StoreDialogState extends State<_StoreDialog> {
  @override
  void initState() {
    super.initState();
    if (widget.upload.quote == null) widget.upload.loadQuote();
  }

  Future<void> _start() async {
    final result = await widget.upload.start();
    if (result != null && mounted) Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final upload = widget.upload;
    return Dialog(
      backgroundColor: Palette.raised,
      insetPadding: const EdgeInsets.all(Space.lg),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.card),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(Space.xl),
          child: ListenableBuilder(
            listenable: upload,
            builder: (context, _) => PopScope(
              canPop: !upload.busy,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(
                    header: true,
                    child: Text(widget.title, style: TextStyles.title),
                  ),
                  const SizedBox(height: Space.lg),
                  WalletWritePanel(
                    upload: upload,
                    onRetry: _start,
                    what: widget.what,
                  ),
                  if (!upload.busy) ...[
                    const SizedBox(height: Space.xl),
                    Wrap(
                      alignment: WrapAlignment.end,
                      spacing: Space.md,
                      runSpacing: Space.sm,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: Text(
                            upload.phase == UploadPhase.failed
                                ? 'Close'
                                : 'Not now',
                          ),
                        ),
                        if (upload.phase == UploadPhase.ready)
                          Press(
                            child: FilledButton.icon(
                              onPressed: _start,
                              icon: const Icon(Icons.upload_rounded),
                              label: const Text('Pay and store'),
                            ),
                          ),
                      ],
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
