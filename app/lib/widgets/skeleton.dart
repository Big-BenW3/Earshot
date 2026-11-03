import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'common.dart';

/// Gently pulses its descendants' [SkeletonBox]es. Static with reduced
/// motion. Content-shaped placeholders keep the layout from jumping when
/// the data arrives.
class SkeletonPulse extends StatefulWidget {
  const SkeletonPulse({super.key, required this.child, this.label = 'Loading'});
  final Widget child;
  final String label;

  @override
  State<SkeletonPulse> createState() => _SkeletonPulseState();
}

class _SkeletonPulseState extends State<SkeletonPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Motion.reduced(context)) {
      _c.value = 1;
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: widget.label,
    liveRegion: true,
    child: ExcludeSemantics(
      child: FadeTransition(
        opacity: Tween(
          begin: 0.55,
          end: 1.0,
        ).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
        child: widget.child,
      ),
    ),
  );
}

class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    this.width,
    required this.height,
    this.radius = 6,
    this.circle = false,
  });
  final double? width;
  final double height;
  final double radius;
  final bool circle;

  @override
  Widget build(BuildContext context) => Container(
    width: circle ? height : width,
    height: height,
    decoration: BoxDecoration(
      color: Palette.raised,
      shape: circle ? BoxShape.circle : BoxShape.rectangle,
      borderRadius: circle ? null : BorderRadius.circular(radius),
    ),
  );
}

class _RowSkeleton extends StatelessWidget {
  const _RowSkeleton();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.lg),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 150, height: 12),
              SizedBox(height: 10),
              SkeletonBox(width: 280, height: 18),
              SizedBox(height: 10),
              SkeletonBox(height: 14),
            ],
          ),
        ),
        SizedBox(width: Space.xxxl),
        SkeletonBox(height: 48, circle: true),
      ],
    ),
  );
}

/// The show page while it loads: cover, title block and three rows.
class ShowSkeleton extends StatelessWidget {
  const ShowSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 820;
    final cover = SkeletonBox(
      width: wide ? 280 : 200,
      height: wide ? 280 : 200,
      radius: Radii.cover,
    );
    const lines = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SkeletonBox(width: 220, height: 12),
        SizedBox(height: Space.lg),
        SkeletonBox(width: 380, height: 44, radius: 8),
        SizedBox(height: Space.md),
        SkeletonBox(width: 160, height: 16),
        SizedBox(height: Space.xl),
        SkeletonBox(height: 14),
        SizedBox(height: 10),
        SkeletonBox(height: 14),
        SizedBox(height: 10),
        SkeletonBox(width: 260, height: 14),
        SizedBox(height: Space.xl),
        Row(
          children: [
            SkeletonBox(width: 150, height: 48, radius: 24),
            SizedBox(width: Space.md),
            SkeletonBox(width: 130, height: 48, radius: 24),
          ],
        ),
      ],
    );
    return PageFrame(
      showFooter: false,
      children: [
        const SizedBox(height: Space.lg),
        SkeletonPulse(
          label: 'Loading show',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (wide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    cover,
                    const SizedBox(width: Space.xxxl),
                    const Expanded(child: lines),
                  ],
                )
              else ...[
                Center(child: cover),
                const SizedBox(height: Space.xl),
                lines,
              ],
              const SizedBox(height: Space.xxxl),
              const SkeletonBox(width: 140, height: 28, radius: 8),
              const SizedBox(height: Space.md),
              const Divider(),
              for (var i = 0; i < 3; i++) ...[
                const _RowSkeleton(),
                const Divider(),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// The episode page while it loads.
class EpisodeSkeleton extends StatelessWidget {
  const EpisodeSkeleton({super.key});

  @override
  Widget build(BuildContext context) => const PageFrame(
    maxWidth: 860,
    showFooter: false,
    children: [
      SkeletonPulse(
        label: 'Loading episode',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: Space.md),
            SkeletonBox(width: 180, height: 16),
            SizedBox(height: Space.xl),
            Row(
              children: [
                SkeletonBox(width: 96, height: 96, radius: 12),
                SizedBox(width: Space.lg),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBox(width: 140, height: 12),
                    SizedBox(height: 10),
                    SkeletonBox(width: 220, height: 12),
                  ],
                ),
              ],
            ),
            SizedBox(height: Space.xl),
            SkeletonBox(width: 420, height: 38, radius: 8),
            SizedBox(height: Space.xl),
            SkeletonBox(height: 120, radius: 20),
            SizedBox(height: Space.xl),
            Row(
              children: [
                SkeletonBox(width: 120, height: 48, radius: 24),
                SizedBox(width: Space.sm),
                SkeletonBox(width: 180, height: 48, radius: 24),
              ],
            ),
          ],
        ),
      ),
    ],
  );
}
