import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Scales its child to 0.97 while pressed: quick in (100 ms), a little
/// slower out (160 ms), strong ease-out. No movement with reduced motion.
class Press extends StatefulWidget {
  const Press({super.key, required this.child, this.scale = 0.97});

  final Widget child;
  final double scale;

  @override
  State<Press> createState() => _PressState();
}

class _PressState extends State<Press> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    if (Motion.reduced(context)) return widget.child;
    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        duration: _down ? Motion.press : Motion.release,
        curve: Motion.out,
        child: widget.child,
      ),
    );
  }
}

/// An InkWell that draws a 2 px amber focus ring when it has keyboard focus
/// (the Material focus overlay alone is too faint on walnut).
class RingInkWell extends StatefulWidget {
  const RingInkWell({
    super.key,
    required this.child,
    required this.onTap,
    this.radius = Radii.card,
    this.pressScale,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double radius;

  /// Optional press scale for large surfaces (0.99 reads as a nudge).
  final double? pressScale;

  @override
  State<RingInkWell> createState() => _RingInkWellState();
}

class _RingInkWellState extends State<RingInkWell> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final keyboard =
        FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    final radius = BorderRadius.circular(widget.radius);
    Widget ink = InkWell(
      onTap: widget.onTap,
      borderRadius: radius,
      focusColor: Colors.transparent,
      onFocusChange: (f) => setState(() => _focused = f),
      child: widget.child,
    );
    if (widget.pressScale != null) {
      ink = Press(scale: widget.pressScale!, child: ink);
    }
    return Stack(
      children: [
        ink,
        if (_focused && keyboard)
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: radius,
                  border: Border.all(color: Palette.amber, width: 2),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
