import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../models/models.dart';
import '../services/services.dart';
import '../theme/tokens.dart';
import '../util/format.dart';
import 'press.dart';

/// Scrollable page with centred content, gutters, header and footer.
class PageFrame extends StatelessWidget {
  const PageFrame({
    super.key,
    required this.children,
    this.maxWidth = Space.contentWidth,
    this.headerTrailing,
    this.showFooter = true,
  });

  final List<Widget> children;
  final double maxWidth;
  final Widget? headerTrailing;
  final bool showFooter;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final gutter = Space.gutter(c.maxWidth);
        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: _Centered(
                maxWidth: maxWidth,
                gutter: gutter,
                child: SiteHeader(trailing: headerTrailing),
              ),
            ),
            SliverToBoxAdapter(
              child: _Centered(
                maxWidth: maxWidth,
                gutter: gutter,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children,
                ),
              ),
            ),
            if (showFooter)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: _Centered(
                    maxWidth: maxWidth,
                    gutter: gutter,
                    child: const SiteFooter(),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Centered extends StatelessWidget {
  const _Centered({
    required this.maxWidth,
    required this.gutter,
    required this.child,
  });
  final double maxWidth;
  final double gutter;
  final Widget child;

  @override
  Widget build(BuildContext context) => Center(
    heightFactor: 1,
    child: _MaxWidth(
      maxWidth: maxWidth + gutter * 2,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: gutter),
        child: child,
      ),
    ),
  );
}

/// Like `ConstrainedBox(maxWidth: ...)`, but also clamps the width used for
/// intrinsic height. `SliverFillRemaining` sizes the footer from intrinsic
/// height, and text that wraps needs the real width to be measured right.
class _MaxWidth extends SingleChildRenderObjectWidget {
  const _MaxWidth({required this.maxWidth, super.child});
  final double maxWidth;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMaxWidth(maxWidth);

  @override
  void updateRenderObject(BuildContext context, _RenderMaxWidth renderObject) =>
      renderObject.maxWidth = maxWidth;
}

class _RenderMaxWidth extends RenderConstrainedBox {
  _RenderMaxWidth(double maxWidth)
    : _maxWidth = maxWidth,
      super(additionalConstraints: BoxConstraints(maxWidth: maxWidth));

  double _maxWidth;
  set maxWidth(double v) {
    _maxWidth = v;
    additionalConstraints = BoxConstraints(maxWidth: v);
  }

  @override
  double computeMinIntrinsicHeight(double width) =>
      super.computeMinIntrinsicHeight(math.min(width, _maxWidth));

  @override
  double computeMaxIntrinsicHeight(double width) =>
      super.computeMaxIntrinsicHeight(math.min(width, _maxWidth));
}

/// The Earshot mark: a walnut ear around a play key on an amber tile.
/// Small sizes use the simplified flat version so the play key survives.
class EarshotMark extends StatelessWidget {
  const EarshotMark({super.key, this.size = 32});
  final double size;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(size * 0.22),
    child: Image.asset(
      size <= 40
          ? 'assets/brand/earshot-mark-small-96.png'
          : 'assets/brand/earshot-mark-256.png',
      width: size,
      height: size,
      filterQuality: FilterQuality.medium,
      excludeFromSemantics: true,
    ),
  );
}

class SiteHeader extends StatelessWidget {
  const SiteHeader({super.key, this.trailing});
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.lg),
      child: Row(
        children: [
          Semantics(
            link: true,
            label: 'Earshot home',
            child: RingInkWell(
              onTap: () => context.go('/app'),
              radius: Radii.small,
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 7, horizontal: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ExcludeSemantics(child: EarshotMark(size: 30)),
                    SizedBox(width: 10),
                    ExcludeSemantics(
                      child: Text(
                        'Earshot',
                        style: TextStyle(
                          fontFamily: Fonts.display,
                          fontSize: 22,
                          color: Palette.cream,
                          height: 1,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const Spacer(),
          // The account chip may shrink (its label ellipsizes) on phones.
          if (trailing != null)
            Flexible(
              flex: 1000,
              child: Align(alignment: Alignment.centerRight, child: trailing),
            ),
        ],
      ),
    );
  }
}

class SiteFooter extends StatelessWidget {
  const SiteFooter({super.key});

  @override
  Widget build(BuildContext context) {
    final network = context.services.config.network;
    return Padding(
      padding: const EdgeInsets.only(top: Space.huge, bottom: Space.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(),
          const SizedBox(height: Space.lg),
          Wrap(
            spacing: Space.lg,
            runSpacing: Space.xs,
            children: [
              Text(
                'Built with Dartus',
                style: TextStyles.small.copyWith(color: Palette.cream),
              ),
              Text(
                'Audio stored on Walrus${network == 'custom' ? '' : ' $network'}',
                style: TextStyles.small,
              ),
              const Text('MIT licensed', style: TextStyles.small),
            ],
          ),
        ],
      ),
    );
  }
}

/// Upper-case mono label, e.g. "PINNED · START HERE".
class Overline extends StatelessWidget {
  const Overline(this.text, {super.key, this.color});
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: TextStyles.overline.copyWith(color: color),
  );
}

/// A pulsing row of dial ticks.
class DialLoader extends StatefulWidget {
  const DialLoader({super.key, this.label = 'Loading'});
  final String label;

  @override
  State<DialLoader> createState() => _DialLoaderState();
}

class _DialLoaderState extends State<DialLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.maybeDisableAnimationsOf(context) == true) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.label,
      liveRegion: true,
      child: ExcludeSemantics(
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) => Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < 7; i++)
                Container(
                  width: 3,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  height:
                      10 +
                      18 *
                          math.max(
                            0,
                            math.sin((_c.value * 2 * math.pi) - i * 0.6),
                          ),
                  decoration: BoxDecoration(
                    color: i == 3 ? Palette.amber : Palette.faint,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class LoadingState extends StatelessWidget {
  const LoadingState({super.key, this.label = 'Loading'});
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 96),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DialLoader(label: label),
          const SizedBox(height: Space.lg),
          Text(label, style: TextStyles.small),
        ],
      ),
    ),
  );
}

/// Message block for empty, error, not-found and expired states.
class MessageState extends StatelessWidget {
  const MessageState({
    super.key,
    required this.title,
    required this.body,
    this.icon = Icons.radio_outlined,
    this.tone = Palette.muted,
    this.action,
  });

  final String title;
  final String body;
  final IconData icon;
  final Color tone;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 72),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 40, color: tone),
              const SizedBox(height: Space.lg),
              Text(title, style: TextStyles.title, textAlign: TextAlign.center),
              const SizedBox(height: Space.sm),
              Text(
                body,
                style: TextStyles.bodyMuted,
                textAlign: TextAlign.center,
              ),
              if (action != null) ...[
                const SizedBox(height: Space.xl),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => MessageState(
    title: 'Something went wrong',
    body: message,
    icon: Icons.portable_wifi_off_rounded,
    tone: Palette.tube,
    action: Press(
      child: OutlinedButton.icon(
        onPressed: onRetry,
        icon: const Icon(Icons.refresh_rounded),
        label: const Text('Try again'),
      ),
    ),
  );
}

class NotFoundState extends StatelessWidget {
  const NotFoundState({super.key, this.title = 'Nothing here', this.body});
  final String title;
  final String? body;

  @override
  Widget build(BuildContext context) => MessageState(
    title: title,
    body: body ?? 'The link may be mistyped, or the show was never created.',
    icon: Icons.search_off_rounded,
    action: Press(
      child: FilledButton(
        onPressed: () => context.go('/app'),
        child: const Text('Go to Earshot'),
      ),
    ),
  );
}

void showToast(BuildContext context, String message) {
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

Future<void> copyToClipboard(
  BuildContext context,
  String text,
  String what,
) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) showToast(context, '$what copied');
}

/// A labelled, copyable value (links, blob IDs).
class CopyField extends StatelessWidget {
  const CopyField({
    super.key,
    required this.label,
    required this.value,
    this.help,
    this.mono = false,
    this.emphasis = false,
  });

  final String label;
  final String value;
  final String? help;
  final bool mono;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        Space.lg,
        Space.md,
        Space.sm,
        Space.md,
      ),
      decoration: BoxDecoration(
        color: Palette.surface,
        borderRadius: BorderRadius.circular(Radii.card),
        border: Border.all(color: emphasis ? Palette.amber : Palette.line),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Overline(
                  label,
                  color: emphasis ? Palette.amber : Palette.muted,
                ),
                const SizedBox(height: Space.xs),
                SelectableText(
                  value,
                  style: mono
                      ? TextStyles.timecode.copyWith(
                          color: Palette.cream,
                          fontSize: 14,
                        )
                      : TextStyles.body,
                ),
                if (help != null) ...[
                  const SizedBox(height: Space.xs),
                  Text(help!, style: TextStyles.small),
                ],
              ],
            ),
          ),
          const SizedBox(width: Space.sm),
          IconButton(
            tooltip: 'Copy ${label.toLowerCase()}',
            onPressed: () => copyToClipboard(context, value, label),
            icon: const Icon(Icons.copy_rounded, size: 20),
          ),
        ],
      ),
    );
  }
}

/// Square cover art read from Walrus through Dartus, with a warm placeholder.
class CoverArt extends StatefulWidget {
  const CoverArt({
    super.key,
    required this.show,
    required this.size,
    this.radius,
  });

  final Show show;
  final double size;
  final double? radius;

  @override
  State<CoverArt> createState() => _CoverArtState();
}

class _CoverArtState extends State<CoverArt> {
  Future<Uint8List>? _bytes;
  String? _for;

  void _load() {
    final id = widget.show.coverBlobId;
    if (id == _for) return;
    _for = id;
    _bytes = id == null ? null : context.services.walrus.readImage(id);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  @override
  void didUpdateWidget(CoverArt oldWidget) {
    super.didUpdateWidget(oldWidget);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(
      widget.radius ?? Radii.cover * widget.size / 240,
    );
    final placeholder = _Placeholder(name: widget.show.name, size: widget.size);
    return Semantics(
      image: true,
      label: 'Cover art for ${widget.show.name}',
      child: ClipRRect(
        borderRadius: radius,
        child: SizedBox.square(
          dimension: widget.size,
          child: _bytes == null
              ? placeholder
              : FutureBuilder<Uint8List>(
                  future: _bytes,
                  builder: (context, snap) {
                    if (snap.hasData) {
                      return Image.memory(
                        snap.data!,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                        errorBuilder: (_, _, _) => placeholder,
                      );
                    }
                    return placeholder;
                  },
                ),
        ),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.name, required this.size});
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty
        ? 'E'
        : name.trim().characters.first.toUpperCase();
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF4A2F1E), Color(0xFF241812)],
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _TicksPainter())),
          Center(
            child: Text(
              initial,
              style: TextStyle(
                fontFamily: Fonts.display,
                fontSize: size * 0.42,
                color: Palette.amber,
                height: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TicksPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Palette.amber.withValues(alpha: 0.28)
      ..strokeWidth = math.max(1, size.width / 160);
    final y = size.height * 0.84;
    final n = 24;
    for (var i = 0; i <= n; i++) {
      final x = size.width * (0.12 + 0.76 * i / n);
      final h = size.height * (i % 4 == 0 ? 0.06 : 0.03);
      canvas.drawLine(Offset(x, y - h), Offset(x, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// "Stored on Walrus" details for an episode or upload.
class WalrusNote extends StatelessWidget {
  const WalrusNote({
    super.key,
    required this.blobId,
    this.endEpoch,
    this.extra,
  });
  final String blobId;
  final int? endEpoch;
  final String? extra;

  @override
  Widget build(BuildContext context) {
    final network = context.services.config.network;
    return Container(
      padding: const EdgeInsets.all(Space.lg),
      decoration: BoxDecoration(
        color: Palette.surface,
        borderRadius: BorderRadius.circular(Radii.card),
        border: Border.all(color: Palette.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.inventory_2_outlined,
                size: 18,
                color: Palette.amber,
              ),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Text(
                  'Stored on Walrus${network == 'custom' ? '' : ' $network'}',
                  style: TextStyles.label,
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.md),
          Row(
            children: [
              const Text('Blob ID  ', style: TextStyles.small),
              Expanded(
                child: Tooltip(
                  message: blobId,
                  child: Text(
                    shortId(blobId),
                    style: TextStyles.timecode.copyWith(color: Palette.cream),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Copy blob ID',
                onPressed: () => copyToClipboard(context, blobId, 'Blob ID'),
                icon: const Icon(Icons.copy_rounded, size: 18),
              ),
            ],
          ),
          if (endEpoch != null)
            Text(
              'Stored until Walrus epoch $endEpoch',
              style: TextStyles.small,
            ),
          if (extra != null) ...[
            const SizedBox(height: Space.sm),
            Text(
              extra!,
              style: TextStyles.small.copyWith(color: Palette.faint),
            ),
          ],
        ],
      ),
    );
  }
}
