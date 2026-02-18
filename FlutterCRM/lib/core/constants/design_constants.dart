import 'package:flutter/material.dart';

class DesignConstants {
  static const Color primaryColor = Color(0xFFFF6C2D);
  static final Color primaryColor50 = primaryColor.withValues(alpha: 0.5);
  static final Color primaryColor25 = primaryColor.withValues(alpha: 0.25);
  static final Color primaryColor10 = primaryColor.withValues(alpha: 0.1);

  static final Color darkPrimary = Color(0xFF692F16);

  static const Color backgroundColor = Color(0xFF121619);

  static const Color text = Color(0xFFF4F3EE);
  static final Color text2nd = text.withValues(alpha: 0.75);
  static final Color text3rd = text.withValues(alpha: 0.50);

  static final Color card = text.withValues(alpha: 0.1);

  static const Color hyperlink = Color(0xFF83C7FF);
  static const Color goodGreen = Color(0xFF74F394);
  static const Color okYellow = Color(0xFFCCCE44);
  static const Color badRed = Color(0xFFF94A4D);

  // Aliases for consistency
  static const Color primary = primaryColor;
  static const Color secondary = hyperlink;
  static const Color background = backgroundColor;
  static const Color cardBackground = Color(0xFF1A1E22);
  static const Color buttonStroke = Color(0xFF2A2E32);

  // Design values
  static const double radiusBig = 32.0;
  static const double radiusSmall = 16.0;

  static const int paddingBig = 32;
  static const int paddingSmall = 16;

  static const int spacingBig = 32;
  static const int spacingLarge = 16;
  static const int spacingMedium = 8;
  static const int spacingSmall = 4;
  static const int spacingTiny = 2;

  static final int buttonBorder = 2;

  static const double buttonBorderSize = 3.0;
  static const double screenHorizontalPadding = 16.0;

  static const String fontFamily = 'Jura';

  /// H1 text style (light, 30)
  static const TextStyle h1 = TextStyle(
    fontFamily: fontFamily,
    fontWeight: FontWeight.w700,
    fontSize: 24,
    color: text,
    letterSpacing: -0.02,
  );

  static final TextStyle h1Regular = h2.copyWith(fontWeight: FontWeight.w500);
  static final TextStyle big1 = h2.copyWith(fontSize: 160);
  static final TextStyle big2 = h2.copyWith(fontSize: 32);

  /// H2 text style (light, 18)
  static const TextStyle h2 = TextStyle(
    fontFamily: fontFamily,
    fontWeight: FontWeight.w600,
    fontSize: 16,
    color: text,
    letterSpacing: -0.01,
  );

  static final TextStyle h2Regular = h2.copyWith(fontWeight: FontWeight.w400);

  /// H3 text style (regular, 15)
  static const TextStyle h3 = TextStyle(
    fontFamily: fontFamily,
    fontWeight: FontWeight.w600,
    fontSize: 13,
    color: text,
    letterSpacing: 0,
  );

  /// Paragraph text style (regular, 12)
  static const TextStyle p = TextStyle(
    fontFamily: fontFamily,
    fontWeight: FontWeight.w400,
    fontSize: 12,
    color: text,
    letterSpacing: 0.03,
  );

  static final TextStyle pBig = p.copyWith(fontSize: 16);
  static final TextStyle pSmall = p.copyWith(fontSize: 11);

  // Private constructor to prevent instantiation
  DesignConstants._();
}
