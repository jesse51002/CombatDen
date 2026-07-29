import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/shared/themes/transitions/app_page_transitions.dart';

class AppTheme {
  AppTheme._();

  static ThemeData forCanvas() {
    final brightness = DesignConstants.isLightCanvas
        ? Brightness.light
        : Brightness.dark;

    // Start from the matching named scheme (correct brightness +
    // sensible role defaults), then override the branded roles once.
    final base = brightness == Brightness.light
        ? const ColorScheme.light()
        : const ColorScheme.dark();
    final colorScheme = base.copyWith(
      primary: DesignConstants.primaryColor,
      onPrimary: DesignConstants.primaryButtonText,
      secondary: DesignConstants.darkPrimary,
      onSecondary: DesignConstants.text,
      surface: DesignConstants.backgroundColor,
      onSurface: DesignConstants.text,
      error: DesignConstants.badRed,
      onError: DesignConstants.text,
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
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: DesignConstants.backgroundColor,
      textTheme: textTheme,
      iconTheme: IconThemeData(
        color: DesignConstants.text,
        weight: DesignConstants.iconWeight,
      ),
      dividerColor: DesignConstants.divider,
      // Screen-to-screen motion, resolved from the tenant's
      // `transition_style` slot. Installed unconditionally: the
      // builders defer to the slot at the moment a route animates, and
      // the shipped value hands the route straight back to the
      // framework's own platform default.
      pageTransitionsTheme: AppPageTransitions.theme(),
    );
  }
}
