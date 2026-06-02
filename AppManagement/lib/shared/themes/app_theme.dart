import 'package:flutter/material.dart';
import 'package:app_management/core/constants/design_constants.dart';

class AppTheme {
  AppTheme._();

  static ThemeData get light {
    final colorScheme = ColorScheme.light(
      primary: DesignConstants.primaryColor,
      onPrimary: DesignConstants.surface,
      secondary: DesignConstants.darkPrimary,
      onSecondary: DesignConstants.surface,
      surface: DesignConstants.backgroundColor,
      onSurface: DesignConstants.text,
      error: DesignConstants.badRed,
      onError: DesignConstants.surface,
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
      brightness: Brightness.light,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: DesignConstants.backgroundColor,
      textTheme: textTheme,
      iconTheme: IconThemeData(
        color: DesignConstants.text,
        weight: DesignConstants.iconWeight,
      ),
      dividerColor: DesignConstants.divider,
    );
  }
}
