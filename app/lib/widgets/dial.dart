import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/tokens.dart';
import '../util/format.dart';
import 'press.dart';

/// The round amber play key.
class PlayKey extends StatelessWidget {
  const PlayKey({
    super.key,
    required this.playing,
    required this.onPressed,
    this.size = 56,
    this.loading = false,
    this.outlined = false,
    this.progress,
    this.label,
  });

  final bool playing;
  final bool loading;
  final VoidCallback? onPressed;
  final double size;

  /// Outlined keys are used in lists; filled keys are the main control.
  final bool outlined;

  /// Listened fraction drawn as a ring (lists only).
  final double? progress;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final fg = outlined ? Palette.amber : Palette.night;
    final icon = loading
        ? SizedBox.square(
            dimension: size * 0.36,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: fg,
              backgroundColor: Colors.transparent,
            ),
          )
        : Icon(
            playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            key: ValueKey(playing),
            size: size * 0.5,
            color: fg,
          );
    return Semantics(
      button: true,
      label: label ?? (playing ? 'Pause' : 'Play'),
      child: Press(
        child: SizedBox.square(
          dimension: size,
          child: CustomPaint(
            painter: progress == null
                ? null
                : _RingPainter(progress!.clamp(0.0, 1.0)),
            child: Padding(
              padding: EdgeInsets.all(progress == null ? 0 : 4),
              child: Material(
                color: outlined ? Colors.transparent : Palette.amber,
                shape: CircleBorder(
                  side: outlined
                      ? const BorderSide(color: Palette.amber, width: 1.5)
                      : BorderSide.none,
                ),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onPressed,
                  focusColor: Palette.glow.withValues(alpha: 0.35),
                  child: Center(
                    // No swap animation: play/pause is also driven by the
                    // keyboard (K, Space), and keyboard actions never animate.
                    // The play triangle is nudged right by ~4% of the key so
                    // it looks centred (its mass sits left of its box).
                    child: Padding(
                      padding: EdgeInsets.only(
                        left: playing || loading ? 0 : size * 0.04,
                      ),
                      child: ExcludeSemantics(child: icon),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.value);
  final double value;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Palette.line;
    canvas.drawArc(rect.deflate(1), 0, math.pi * 2, false, track);
    if (value <= 0) return;
    canvas.drawArc(
      rect.deflate(1),
      -math.pi / 2,
      math.pi * 2 * value,
      false,
      track..color = Palette.glow,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.value != value;
}

/// The seek bar, drawn as a radio tuning scale with a needle.
class DialSlider extends StatefulWidget {
  const DialSlider({
    super.key,
    required this.position,
    required this.duration,
    required this.onSeek,
    this.height = 44,
    this.dense = false,
  });

  final Duration position;
  final Duration? duration;
  final ValueChanged<Duration> onSeek;
  final double height;
  final bool dense;

  @override
  State<DialSlider> createState() => _DialSliderState();
}

class _DialSliderState extends State<DialSlider> {
  double? _drag;
  bool _focused = false;

  double get _fraction {
    if (_drag != null) return _drag!;
    final d = widget.duration;
    if (d == null || d.inMilliseconds == 0) return 0;
    return (widget.position.inMilliseconds / d.inMilliseconds).clamp(0.0, 1.0);
  }

  void _seekFraction(double f) {
    final d = widget.duration;
    if (d == null) return;
    widget.onSeek(d * f.clamp(0.0, 1.0));
  }

  void _nudge(Duration by) {
    final d = widget.duration;
    if (d == null) return;
    var t = widget.position + by;
    if (t < Duration.zero) t = Duration.zero;
    if (t > d) t = d;
    widget.onSeek(t);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.arrowRight || k == LogicalKeyboardKey.arrowUp) {
      _nudge(const Duration(seconds: 5));
    } else if (k == LogicalKeyboardKey.arrowLeft ||
        k == LogicalKeyboardKey.arrowDown) {
      _nudge(const Duration(seconds: -5));
    } else if (k == LogicalKeyboardKey.pageUp) {
      _nudge(const Duration(seconds: 30));
    } else if (k == LogicalKeyboardKey.pageDown) {
      _nudge(const Duration(seconds: -30));
    } else if (k == LogicalKeyboardKey.home) {
      _seekFraction(0);
    } else if (k == LogicalKeyboardKey.end) {
      _seekFraction(1);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.duration;
    final enabled = d != null && d > Duration.zero;
    final value = enabled
        ? '${clock(widget.position)} of ${clock(d)}'
        : 'Length unknown';
    return Semantics(
      slider: true,
      label: 'Seek',
      value: value,
      enabled: enabled,
      increasedValue: enabled
          ? clock(widget.position + const Duration(seconds: 5))
          : null,
      decreasedValue: enabled
          ? clock(widget.position - const Duration(seconds: 5))
          : null,
      onIncrease: enabled ? () => _nudge(const Duration(seconds: 5)) : null,
      onDecrease: enabled ? () => _nudge(const Duration(seconds: -5)) : null,
      child: Focus(
        canRequestFocus: enabled,
        onKeyEvent: _onKey,
        onFocusChange: (f) => setState(() => _focused = f),
        child: MouseRegion(
          cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
          child: LayoutBuilder(
            builder: (context, c) {
              double at(double dx) => (dx / c.maxWidth).clamp(0.0, 1.0);
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                // The slider semantics above already offer increase and
                // decrease; raw tap and scroll actions would only confuse.
                excludeFromSemantics: true,
                onTapUp: enabled
                    ? (e) => _seekFraction(at(e.localPosition.dx))
                    : null,
                onHorizontalDragStart: enabled
                    ? (e) => setState(() => _drag = at(e.localPosition.dx))
                    : null,
                onHorizontalDragUpdate: enabled
                    ? (e) => setState(() => _drag = at(e.localPosition.dx))
                    : null,
                onHorizontalDragEnd: enabled
                    ? (_) {
                        final f = _drag;
                        setState(() => _drag = null);
                        if (f != null) _seekFraction(f);
                      }
                    : null,
                child: SizedBox(
                  height: widget.height,
                  width: double.infinity,
                  child: CustomPaint(
                    painter: _DialPainter(
                      fraction: _fraction,
                      enabled: enabled,
                      focused: _focused,
                      dense: widget.dense,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _DialPainter extends CustomPainter {
  _DialPainter({
    required this.fraction,
    required this.enabled,
    required this.focused,
    required this.dense,
  });

  final double fraction;
  final bool enabled;
  final bool focused;
  final bool dense;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final mid = size.height / 2;
    final base = mid + (dense ? 5 : 7);
    final played = w * fraction;

    // Baseline.
    canvas.drawLine(
      Offset(0, base),
      Offset(w, base),
      Paint()
        ..color = Palette.line
        ..strokeWidth = 2,
    );
    canvas.drawLine(
      Offset(0, base),
      Offset(played, base),
      Paint()
        ..color = enabled ? Palette.glow : Palette.faint
        ..strokeWidth = 2,
    );

    // Ticks every 2.5%, a taller one every 5th.
    const count = 40;
    for (var i = 0; i <= count; i++) {
      final x = w * i / count;
      final major = i % 5 == 0;
      final h = major ? (dense ? 9.0 : 12.0) : (dense ? 4.0 : 6.0);
      canvas.drawLine(
        Offset(x, base - 2),
        Offset(x, base - 2 - h),
        Paint()
          ..strokeWidth = major ? 1.6 : 1.2
          ..color = x <= played && enabled
              ? Palette.glow.withValues(alpha: major ? 0.95 : 0.7)
              : Palette.faint.withValues(alpha: major ? 0.75 : 0.45),
      );
    }

    if (!enabled) return;
    // Needle with a soft halo.
    final top = dense ? 2.0 : 0.0;
    final bottom = base + (dense ? 5 : 7);
    canvas.drawLine(
      Offset(played, top),
      Offset(played, bottom),
      Paint()
        ..color = Palette.amber.withValues(alpha: 0.35)
        ..strokeWidth = focused ? 12 : 8
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawLine(
      Offset(played, top),
      Offset(played, bottom),
      Paint()
        ..color = Palette.amber
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
    if (focused) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(-4, 0, w + 8, size.height),
          const Radius.circular(6),
        ),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Palette.amber,
      );
    }
  }

  @override
  bool shouldRepaint(_DialPainter old) =>
      old.fraction != fraction ||
      old.enabled != enabled ||
      old.focused != focused;
}
