import 'package:flutter/material.dart';

/// Colour tokens.
abstract final class Palette {
  static const night = Color(0xFF140D09);
  static const walnut = Color(0xFF1E1510);
  static const surface = Color(0xFF2A1D16);
  static const raised = Color(0xFF36271E);
  static const line = Color(0xFF4A372B);
  static const cream = Color(0xFFF6EBDD);
  static const muted = Color(0xFFCDB9A5);
  static const faint = Color(0xFF9C8572);
  static const amber = Color(0xFFF4A93B);
  static const amberDeep = Color(0xFFD98E1F);
  static const glow = Color(0xFFFFD08A);
  static const moss = Color(0xFF9CCB98);
  static const tube = Color(0xFFFF8C6E);
}

abstract final class Space {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
  static const xxxl = 48.0;
  static const huge = 64.0;

  /// Page gutter by width: 16 phone, 24 tablet, 32 desktop.
  static double gutter(double width) => width < 600
      ? 16
      : width < 1024
      ? 24
      : 32;

  static const contentWidth = 1080.0;
  static const readingWidth = 680.0;
}

abstract final class Radii {
  static const small = 8.0;
  static const card = 14.0;
  static const cover = 18.0;
  static const pill = 999.0;
}

/// Motion vocabulary. Enter with a strong
/// ease-out, leave faster than you came, never animate keyboard actions,
/// and drop movement entirely when the OS asks for reduced motion.
abstract final class Motion {
  /// Press-in feedback (scale 0.97).
  static const press = Duration(milliseconds: 100);

  /// Release from a press, and hover/colour changes.
  static const release = Duration(milliseconds: 160);

  /// Elements appearing: sheets, the player bar, popovers.
  static const enter = Duration(milliseconds: 240);

  /// Elements leaving: always quicker than they arrived.
  static const exit = Duration(milliseconds: 160);

  /// Page changes inside the app.
  static const page = Duration(milliseconds: 180);
  static const pageExit = Duration(milliseconds: 120);

  /// Strong ease-out for UI (cubic-bezier(0.23, 1, 0.32, 1)).
  static const out = Cubic(0.23, 1, 0.32, 1);

  /// On-screen movement (cubic-bezier(0.77, 0, 0.175, 1)).
  static const inOut = Cubic(0.77, 0, 0.175, 1);

  /// iOS-like drawer curve for sheets (cubic-bezier(0.32, 0.72, 0, 1)).
  static const drawer = Cubic(0.32, 0.72, 0, 1);

  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) == true;

  /// Zero when the platform asks for reduced motion.
  static Duration of(BuildContext context, Duration d) =>
      reduced(context) ? Duration.zero : d;

  /// Sheet timing: slower in, quick out; none with reduced motion.
  static AnimationStyle sheet(BuildContext context) => reduced(context)
      ? AnimationStyle.noAnimation
      : const AnimationStyle(
          duration: Duration(milliseconds: 280),
          reverseDuration: Duration(milliseconds: 180),
          curve: drawer,
          reverseCurve: Curves.easeOutCubic,
        );

  /// Small popovers and dialogs.
  static AnimationStyle popover(BuildContext context) => reduced(context)
      ? AnimationStyle.noAnimation
      : const AnimationStyle(
          duration: Duration(milliseconds: 180),
          reverseDuration: Duration(milliseconds: 120),
          curve: out,
          reverseCurve: Curves.easeOutCubic,
        );
}

abstract final class Fonts {
  static const display = 'YoungSerif';
  static const ui = 'HankenGrotesk';
  static const mono = 'DMMono';
}

/// Type scale. Display sizes shrink below 600 px wide.
abstract final class TextStyles {
  static TextStyle display(bool compact) => TextStyle(
    fontFamily: Fonts.display,
    fontSize: compact ? 34 : 48,
    height: compact ? 40 / 34 : 56 / 48,
    color: Palette.cream,
    letterSpacing: -0.5,
  );

  static TextStyle headline(bool compact) => TextStyle(
    fontFamily: Fonts.display,
    fontSize: compact ? 28 : 34,
    height: compact ? 34 / 28 : 40 / 34,
    color: Palette.cream,
    letterSpacing: -0.3,
  );

  static const title = TextStyle(
    fontFamily: Fonts.display,
    fontSize: 24,
    height: 30 / 24,
    color: Palette.cream,
  );

  static const itemTitle = TextStyle(
    fontFamily: Fonts.ui,
    fontSize: 18,
    height: 24 / 18,
    fontWeight: FontWeight.w600,
    color: Palette.cream,
  );

  static const body = TextStyle(
    fontFamily: Fonts.ui,
    fontSize: 16,
    height: 24 / 16,
    fontWeight: FontWeight.w400,
    color: Palette.cream,
  );

  static const bodyMuted = TextStyle(
    fontFamily: Fonts.ui,
    fontSize: 16,
    height: 24 / 16,
    fontWeight: FontWeight.w400,
    color: Palette.muted,
  );

  static const label = TextStyle(
    fontFamily: Fonts.ui,
    fontSize: 15,
    height: 20 / 15,
    fontWeight: FontWeight.w600,
    color: Palette.cream,
  );

  static const small = TextStyle(
    fontFamily: Fonts.ui,
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w500,
    color: Palette.muted,
  );

  static const overline = TextStyle(
    fontFamily: Fonts.mono,
    fontSize: 12,
    height: 16 / 12,
    fontWeight: FontWeight.w500,
    letterSpacing: 1.2,
    color: Palette.amber,
  );

  static const timecode = TextStyle(
    fontFamily: Fonts.mono,
    fontSize: 13,
    height: 16 / 13,
    fontWeight: FontWeight.w400,
    color: Palette.muted,
    fontFeatures: [FontFeature.tabularFigures()],
  );
}
