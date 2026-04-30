import 'package:flutter/material.dart';
import 'package:app_management/core/constants/design_constants.dart';

class AppTheme {
  AppTheme._();

  static ThemeData get dark {
    final colorScheme = ColorScheme.dark(
      primary: DesignConstants.primaryColor,
      onPrimary: DesignConstants.text,
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
      brightness: Brightness.dark,
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
