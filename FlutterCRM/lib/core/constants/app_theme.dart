import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';

/// App-wide [ThemeData] built from [DesignConstants].
class AppTheme {
  static ThemeData get dark => ThemeData.dark().copyWith(
        scaffoldBackgroundColor:
            DesignConstants.backgroundColor,
        scrollbarTheme: ScrollbarThemeData(
          thumbColor: WidgetStatePropertyAll(
            DesignConstants.text3rd,
          ),
        ),
      );

  AppTheme._();
}
