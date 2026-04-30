import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

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
  static final Color popup = Color.alphaBlend(
    backgroundColor, 
    text.withValues(alpha: 0.05)
    );

  static const Color hyperlink = Color(0xFF83C7FF);
  static const Color goodGreen = Color(0xFF74F394);
  static const Color okYellow = Color(0xFFCCCE44);
  static const Color badRed = Color(0xFFF94A4D);

  static final Color yellowDark = Color(0xFF83852F).withValues(alpha: 0.25);
  static final Color greenDark = Color(0xFF0E7A29).withValues(alpha: 0.25);
  static final Color purpleDark = Color(0xFF744373).withValues(alpha: 0.25);
  static final Color blueDark = Color(0xFF425E67).withValues(alpha: 0.25);
  static final Color redDark = Color(0xFF6D2C22).withValues(alpha: 0.25);


  // Design values
  static const double radiusBig = 32.0;
  static const double radiusSmall = 16.0;
  static const double radiusCircle = 1000.0;

  static const double paddingBig = 32;
  static const double paddingSmall = 16;

  static const double spacingBig = 32;
  static const double spacingLarge = 16;
  static const double spacingMedium = 8;
  static const double spacingSmall = 4;
  static const double spacingTiny = 2;

  static final double buttonBorder = 2;
  static final double iconWeight = 300.0;

  static const double buttonBorderSize = 3.0;
  static const double screenHorizontalPadding = 16.0;

  // Icon sizes (T-shirt scale, 16 + 4x)
  static const double iconSizeXs = 16;
  static const double iconSizeSm = 20;
  static const double iconSizeMd = 24;
  static const double iconSizeLg = 28;
  static const double iconSizeXl = 32;
  static const double iconSize2xl = 36;

  // Pill heights
  static const double pillHeightSm = 24;
  static const double pillHeightMd = 30;

  // Divider thickness (single source of truth for hairline dividers)
  static const double dividerThickness = 1;

  static final Color divider = card;
  static const double sideNavWidth = 100.0;
  static const double tableRowHeight = 35.0;

  static final TextStyle baseFont = GoogleFonts.jura();

  /// H1 text style (light, 30)
  static final TextStyle h1 = baseFont.copyWith(
    fontWeight: FontWeight.w700,
    fontSize: 24,
    color: text,
    letterSpacing: -0.02,
  );

  static final TextStyle h1Regular = h1.copyWith(fontWeight: FontWeight.w500);
  static final TextStyle big1 = h2.copyWith(fontSize: 160);
  static final TextStyle big1_5 = h2.copyWith(fontSize: 64);
  static final TextStyle big2 = h2.copyWith(fontSize: 32);

  /// H2 text style (light, 18)
  static final TextStyle h2 = baseFont.copyWith(
    fontWeight: FontWeight.w600,
    fontSize: 16,
    color: text,
    letterSpacing: 0,
  );

  static final TextStyle h2Regular = h2.copyWith(fontWeight: FontWeight.w400,
    letterSpacing: 0.03,
  );

  static final TextStyle h2Bold = h2.copyWith(fontWeight: FontWeight.w700);

  /// H3 text style (regular, 15)
  static final TextStyle h3 = baseFont.copyWith(
    fontWeight: FontWeight.w600,
    fontSize: 13,
    color: text,
    letterSpacing: 0,
  );

  /// Paragraph text style (regular, 12)
  static final TextStyle p = TextStyle(
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
