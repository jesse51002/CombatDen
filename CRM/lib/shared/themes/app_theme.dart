import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/state/theme_controller.dart';

class AppTheme {
  AppTheme._();

  /// The active [ThemeData], resolved from [DesignConstants] for the current
  /// [themeController] mode.
  ///
  /// `DesignConstants` color/text tokens already swap light↔dark on their own,
  /// so this just maps them into Material 3's [ColorScheme] + [TextTheme] at the
  /// matching [Brightness] for the stock widgets that *do* read
  /// `Theme.of(context)` (Switch, Dialog, SnackBar, text selection…). `main.dart`
  /// wraps `MaterialApp` in a `ListenableBuilder` on [themeController] and passes
  /// this, so the whole tree repaints when the mode flips.
  static ThemeData get current {
    final isDark = themeController.isDark;
    // Labels that sit on a filled accent/secondary/error must stay near-white in
    // both themes (a white label in light; the near-white ink in dark).
    final onFilled = isDark ? DesignConstants.text : DesignConstants.surface;

    final base = isDark ? const ColorScheme.dark() : const ColorScheme.light();
    final colorScheme = base.copyWith(
      primary: DesignConstants.primaryColor,
      onPrimary: onFilled,
      secondary: DesignConstants.darkPrimary,
      onSecondary: onFilled,
      surface: DesignConstants.backgroundColor,
      onSurface: DesignConstants.text,
      error: DesignConstants.badRed,
      onError: onFilled,
    );

    final textTheme = TextTheme(
      displayLarge: DesignConstants.big1,
      displayMedium: DesignConstants.big2,
      headlineLarge: DesignConstants.h1,
      headlineMedium: DesignConstants.h1Regular,
      titleLarge: DesignConstants.h2,
      titleMedium: DesignConstants.h2Regular,
      titleSmall: DesignConstants.h3,
      bodyLarge: DesignConstants.pBig,
      bodyMedium: DesignConstants.p,
      bodySmall: DesignConstants.pSmall,
      labelLarge: DesignConstants.h3,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: isDark ? Brightness.dark : Brightness.light,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: DesignConstants.backgroundColor,
      textTheme: textTheme,
      iconTheme: IconThemeData(
        color: DesignConstants.text,
        weight: DesignConstants.iconWeight,
      ),
      dividerColor: DesignConstants.divider,
      // The M3 time picker reads textTheme.displayLarge for its hour/minute
      // digits; ours is `big1` (160px), which clips the digits into garbage.
      // Pin a sane digit style (the picker still resolves the selected-state
      // color itself, so the style's color is overridden).
      timePickerTheme: TimePickerThemeData(
        hourMinuteTextStyle: DesignConstants.big2Bold,
      ),
    );
  }
}
