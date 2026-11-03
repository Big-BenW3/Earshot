import 'package:flutter/material.dart';
import 'package:sui_wallet_web/sui_wallet_web.dart';

import 'tokens.dart';

ThemeData buildTheme() {
  const scheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Palette.amber,
    onPrimary: Palette.night,
    primaryContainer: Palette.raised,
    onPrimaryContainer: Palette.cream,
    secondary: Palette.glow,
    onSecondary: Palette.night,
    error: Palette.tube,
    onError: Palette.night,
    surface: Palette.walnut,
    onSurface: Palette.cream,
    onSurfaceVariant: Palette.muted,
    surfaceContainerLowest: Palette.night,
    surfaceContainerLow: Palette.walnut,
    surfaceContainer: Palette.surface,
    surfaceContainerHigh: Palette.raised,
    surfaceContainerHighest: Palette.raised,
    outline: Palette.faint,
    outlineVariant: Palette.line,
    inverseSurface: Palette.cream,
    onInverseSurface: Palette.night,
  );

  const focusSide = BorderSide(color: Palette.amber, width: 2);
  OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(Radii.small),
    borderSide: BorderSide(color: c, width: w),
  );

  final textTheme =
      const TextTheme(
        displayLarge: TextStyle(fontFamily: Fonts.display),
        headlineMedium: TextStyle(fontFamily: Fonts.display),
        titleLarge: TextStyle(fontFamily: Fonts.display),
        titleMedium: TextStyles.itemTitle,
        bodyLarge: TextStyles.body,
        bodyMedium: TextStyles.body,
        bodySmall: TextStyles.small,
        labelLarge: TextStyles.label,
      ).apply(
        fontFamily: Fonts.ui,
        bodyColor: Palette.cream,
        displayColor: Palette.cream,
      );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Palette.walnut,
    fontFamily: Fonts.ui,
    textTheme: textTheme.copyWith(
      displayLarge: TextStyles.display(false),
      headlineMedium: TextStyles.headline(false),
      titleLarge: TextStyles.title,
    ),
    focusColor: Palette.amber.withValues(alpha: 0.18),
    hoverColor: Palette.cream.withValues(alpha: 0.05),
    highlightColor: Palette.cream.withValues(alpha: 0.06),
    splashFactory: InkRipple.splashFactory,
    extensions: [
      SuiWalletPickerTheme(
        tileColor: Palette.surface,
        tileHoverColor: Palette.raised,
        tileBorderColor: Palette.line,
        tileSelectedBorderColor: Palette.amber,
        tileRadius: BorderRadius.circular(Radii.card),
        minTileHeight: 56,
        focusColor: Palette.amber,
        progressColor: Palette.amber,
        titleStyle: TextStyles.title,
        nameStyle: TextStyles.label,
        bodyStyle: TextStyles.small,
        errorStyle: TextStyles.small.copyWith(color: Palette.tube),
        errorBackgroundColor: Palette.tube.withValues(alpha: 0.12),
        linkStyle: TextStyles.label.copyWith(color: Palette.amber),
      ),
    ],
    // Pages change often: a short fade, no sliding, nothing at all with
    // reduced motion.
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: QuietFadeTransitions(),
        TargetPlatform.iOS: QuietFadeTransitions(),
        TargetPlatform.macOS: QuietFadeTransitions(),
        TargetPlatform.windows: QuietFadeTransitions(),
        TargetPlatform.linux: QuietFadeTransitions(),
        TargetPlatform.fuchsia: QuietFadeTransitions(),
      },
    ),
    dividerTheme: const DividerThemeData(
      color: Palette.line,
      thickness: 1,
      space: 1,
    ),
    iconTheme: const IconThemeData(color: Palette.cream, size: 22),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: Palette.cream,
        borderRadius: BorderRadius.circular(Radii.small),
      ),
      textStyle: TextStyles.small.copyWith(color: Palette.night),
      waitDuration: const Duration(milliseconds: 400),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Palette.cream,
      contentTextStyle: TextStyles.label.copyWith(color: Palette.night),
      actionTextColor: Palette.amberDeep,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.small),
      ),
      insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Palette.surface,
      labelStyle: TextStyles.small,
      floatingLabelStyle: TextStyles.small.copyWith(color: Palette.amber),
      hintStyle: TextStyles.body.copyWith(color: Palette.faint),
      helperStyle: TextStyles.small.copyWith(color: Palette.faint),
      helperMaxLines: 3,
      errorStyle: TextStyles.small.copyWith(color: Palette.tube),
      errorMaxLines: 3,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: border(Palette.faint),
      enabledBorder: border(Palette.faint),
      focusedBorder: border(Palette.amber, 2),
      errorBorder: border(Palette.tube),
      focusedErrorBorder: border(Palette.tube, 2),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.disabled)
              ? Palette.raised
              : s.contains(WidgetState.pressed)
              ? Palette.amberDeep
              : Palette.amber,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (s) =>
              s.contains(WidgetState.disabled) ? Palette.faint : Palette.night,
        ),
        overlayColor: WidgetStatePropertyAll(
          Palette.glow.withValues(alpha: 0.18),
        ),
        textStyle: const WidgetStatePropertyAll(TextStyles.label),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        ),
        minimumSize: const WidgetStatePropertyAll(Size(64, 48)),
        shape: const WidgetStatePropertyAll(StadiumBorder()),
        side: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.focused)
              ? const BorderSide(color: Palette.cream, width: 2)
              : BorderSide.none,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        foregroundColor: const WidgetStatePropertyAll(Palette.cream),
        textStyle: const WidgetStatePropertyAll(TextStyles.label),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
        minimumSize: const WidgetStatePropertyAll(Size(64, 48)),
        shape: const WidgetStatePropertyAll(StadiumBorder()),
        overlayColor: WidgetStatePropertyAll(
          Palette.cream.withValues(alpha: 0.06),
        ),
        side: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.focused)
              ? focusSide
              : const BorderSide(color: Palette.faint),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        foregroundColor: const WidgetStatePropertyAll(Palette.amber),
        textStyle: const WidgetStatePropertyAll(TextStyles.label),
        minimumSize: const WidgetStatePropertyAll(Size(48, 44)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 12),
        ),
        overlayColor: WidgetStatePropertyAll(
          Palette.amber.withValues(alpha: 0.1),
        ),
        shape: WidgetStateProperty.resolveWith(
          (s) => RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.small),
            side: s.contains(WidgetState.focused) ? focusSide : BorderSide.none,
          ),
        ),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        foregroundColor: const WidgetStatePropertyAll(Palette.cream),
        minimumSize: const WidgetStatePropertyAll(Size(44, 44)),
        overlayColor: WidgetStatePropertyAll(
          Palette.cream.withValues(alpha: 0.08),
        ),
        shape: WidgetStateProperty.resolveWith(
          (s) => CircleBorder(
            side: s.contains(WidgetState.focused) ? focusSide : BorderSide.none,
          ),
        ),
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      side: const BorderSide(color: Palette.faint, width: 1.5),
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? Palette.amber
            : Colors.transparent,
      ),
      checkColor: const WidgetStatePropertyAll(Palette.night),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? Palette.night : Palette.muted,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) =>
            s.contains(WidgetState.selected) ? Palette.amber : Palette.surface,
      ),
      trackOutlineColor: const WidgetStatePropertyAll(Palette.faint),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: Palette.amber,
      linearTrackColor: Palette.raised,
      circularTrackColor: Palette.raised,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Palette.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.card),
      ),
      titleTextStyle: TextStyles.title,
      contentTextStyle: TextStyles.body,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: Palette.raised,
      textStyle: TextStyles.body,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.small),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Palette.night,
      modalBackgroundColor: Palette.night,
      showDragHandle: true,
      dragHandleColor: Palette.faint,
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor: Palette.cream,
      unselectedLabelColor: Palette.muted,
      indicatorColor: Palette.amber,
      labelStyle: TextStyles.label,
      unselectedLabelStyle: TextStyles.label,
      dividerColor: Palette.line,
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: Palette.amber,
      selectionColor: Palette.amber.withValues(alpha: 0.35),
      selectionHandleColor: Palette.amber,
    ),
  );
}

/// A 180 ms ease-out fade in, 120 ms out. Pages never slide: navigation is
/// frequent, and movement would only slow it down.
class QuietFadeTransitions extends PageTransitionsBuilder {
  const QuietFadeTransitions();

  @override
  Duration get transitionDuration => Motion.page;

  @override
  Duration get reverseTransitionDuration => Motion.pageExit;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (Motion.reduced(context)) return child;
    return FadeTransition(
      opacity: CurvedAnimation(
        parent: animation,
        curve: Motion.out,
        reverseCurve: Curves.easeOutCubic,
      ),
      child: child,
    );
  }
}
