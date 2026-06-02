import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class DesignConstants {
  // Accent — the single brand blue + its gradient partner. Shared verbatim with
  // the marketing landing page (LandingPage/hifi/ds.jsx `accent`/`accentDark`).
  static const Color primaryColor = Color(0xFF2A67BD);
  static const Color accentDark = Color(0xFF1F5099);
  static const Color accentSoft = Color(0xFFE8F0FB);
  static final Color primaryColor50 = primaryColor.withValues(alpha: 0.5);
  static final Color primaryColor25 = primaryColor.withValues(alpha: 0.25);
  static final Color primaryColor10 = primaryColor.withValues(alpha: 0.1);

  static final Color darkPrimary = Color(0xFF274777);

  // Top-to-bottom gradient for primary actions (landing GWButton primary).
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [primaryColor, accentDark],
  );

  // Landing-aligned light system: cool off-white ground, white lifted surfaces,
  // a cool ink ramp (matches LandingPage/hifi/ds.jsx bg/surface/ink).
  static const Color backgroundColor = Color(0xFFF3F5F8);
  static const Color backgroundAlt = Color(0xFFEEF1F6);
  static const Color surface = Color(0xFFFFFFFF);

  static const Color text = Color(0xFF16181D);
  static const Color text2nd = Color(0xFF565B66);
  static const Color text3rd = Color(0xFF878D99);

  // Cards lift off the cool ground as white surfaces with a hairline border and
  // a soft shadow — never the old flat translucent fill.
  static const Color card = surface;
  // Hairline border / divider (ds.jsx `line`). Decoupled from `card`: a white
  // card with a white divider would be invisible.
  static const Color line = Color.fromARGB(23, 20, 22, 30);
  // Softer hairline (ds.jsx `lineSoft`) — e.g. the mobile menu's link separators.
  static const Color lineSoft = Color.fromARGB(15, 20, 22, 30);
  static const Color divider = line;

  static final Color popup = Color.alphaBlend(
    text.withValues(alpha: 0.04),
    surface,
  );

  static const Color hyperlink = accentDark;
  static const Color goodGreen = Color(0xFF1D7D3E);
  static const Color okYellow = Color(0xFF915C08);
  static const Color badRed = Color(0xFFB6322D);

  static final Color yellowDark = Color(0xFF6D5B35).withValues(alpha: 0.25);
  static final Color greenDark = Color(0xFF395F47).withValues(alpha: 0.25);
  static final Color purpleDark = Color(0xFF5A4E72).withValues(alpha: 0.25);
  static final Color blueDark = Color(0xFF405677).withValues(alpha: 0.25);
  static final Color redDark = Color(0xFF7C423E).withValues(alpha: 0.25);

  // Elevation — soft, layered, diffuse (landing DESIGN.md). Flutter has no CSS
  // `inset`, so the inner highlight from the web shadows is dropped.
  static const List<BoxShadow> cardShadow = [
    BoxShadow(
      color: Color.fromARGB(13, 20, 22, 40),
      blurRadius: 2,
      offset: Offset(0, 1),
    ),
    BoxShadow(
      color: Color.fromARGB(31, 20, 22, 50),
      blurRadius: 30,
      spreadRadius: -10,
      offset: Offset(0, 18),
    ),
  ];

  static const List<BoxShadow> buttonShadow = [
    BoxShadow(
      color: Color.fromARGB(82, 15, 45, 95),
      blurRadius: 2,
      offset: Offset(0, 1),
    ),
    BoxShadow(
      color: Color.fromARGB(128, 30, 80, 160),
      blurRadius: 22,
      spreadRadius: -6,
      offset: Offset(0, 8),
    ),
  ];

  // Subtle neutral lift for small white controls (the mobile menu button).
  static const List<BoxShadow> controlShadow = [
    BoxShadow(
      color: Color.fromARGB(13, 20, 22, 40),
      blurRadius: 2,
      offset: Offset(0, 1),
    ),
  ];

  // Design values
  static const double radiusBig = 12.0;
  static const double radiusSmall = 8.0;
  // Rounder corner for object cards (landing card cells ≈ 22px).
  static const double radiusCard = 20.0;

  static const double paddingBig = 32;
  static const double paddingSmall = 16;

  static const double spacingBig = 32;
  static const double spacingLarge = 16;
  static const double spacingMedium = 8;
  static const double spacingSmall = 4;
  static const double spacingTiny = 2;

  static final double buttonBorder = 2;
  static final double iconWeight = 300.0;

  // Icon sizes — same Big→Tiny cadence as spacing. Medium (20) is the default.
  static const double iconSizeBig = 32;
  static const double iconSizeLarge = 24;
  static const double iconSizeMedium = 20;
  static const double iconSizeSmall = 18;
  static const double iconSizeTiny = 16;

  static const double buttonBorderSize = 3.0;
  static const double screenHorizontalPadding = 16.0;

  static const double sideNavWidth = 100.0;
  static const double quickListWidth = 240.0;
  static const double tableRowHeight = 35.0;

  // Landing-style top nav (LandingPage/hifi/chrome.jsx GWNav).
  static const double navHeight = 68.0;
  static const double navMaxWidth = 1180.0;
  // Below this width the nav collapses to a hamburger + dropdown (ds.jsx
  // MOBILE_Q `(max-width: 768px)`).
  static const double navMobileBreakpoint = 768.0;
  static const double navMenuButtonSize = 42.0;

  // Two lines of h2, so every reward card's title block is the same height
  // whether the title wraps to one line or two.
  static const double rewardCardTitleHeight = 42;

  // Geist — the landing page's typeface (LandingPage/hifi/ds.jsx `sans`).
  static final TextStyle baseFont = GoogleFonts.geist(
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  // Geist Mono — for tracked eyebrow / category micro-labels (ds.jsx `mono`).
  static final TextStyle monoFont = GoogleFonts.geistMono();

  /// H1 text style (bold, 24)
  static final TextStyle h1 = baseFont.copyWith(
    fontWeight: FontWeight.w700,
    fontSize: 24,
    color: text,
    letterSpacing: -0.6,
  );

  static final TextStyle h1Regular = h1.copyWith(fontWeight: FontWeight.w500);
  static final TextStyle big1 = h2.copyWith(fontSize: 160);
  static final TextStyle big2 = h2.copyWith(fontSize: 32);

  static final TextStyle big2Bold = big2.copyWith(fontWeight: FontWeight.w700);
  static final TextStyle big2Light =
      big2.copyWith(fontWeight: FontWeight.w300);

  /// H2 text style (semibold, 16)
  static final TextStyle h2 = baseFont.copyWith(
    fontWeight: FontWeight.w600,
    fontSize: 16,
    color: text,
    letterSpacing: -0.2,
  );

  static final TextStyle h2Regular = h2.copyWith(fontWeight: FontWeight.w400,
    letterSpacing: 0.03,
  );

  static final TextStyle h2Bold = h2.copyWith(fontWeight: FontWeight.w700);

  /// H3 text style (semibold, 13)
  static final TextStyle h3 = baseFont.copyWith(
    fontWeight: FontWeight.w600,
    fontSize: 13,
    color: text,
    letterSpacing: 0,
  );

  /// Paragraph text style (regular, 12)
  static final TextStyle p = baseFont.copyWith(
    fontWeight: FontWeight.w400,
    fontSize: 12,
    color: text,
    letterSpacing: 0.03,
  );

  static final TextStyle pBig = p.copyWith(fontSize: 16);
  static final TextStyle pSmall = p.copyWith(fontSize: 11);

  static final TextStyle pSmallBold =
      pSmall.copyWith(fontWeight: FontWeight.w700);

  // Landing top-nav text: wordmark + nav links (chrome.jsx GWNav).
  static final TextStyle navWordmark = baseFont.copyWith(
    fontWeight: FontWeight.w600,
    fontSize: 18,
    color: text,
    letterSpacing: -0.4,
  );

  static final TextStyle navLink = baseFont.copyWith(
    fontWeight: FontWeight.w500,
    fontSize: 14.5,
    color: text2nd,
    letterSpacing: -0.1,
  );

  // Larger, ink-colored nav link for the mobile dropdown rows.
  static final TextStyle navLinkMobile = baseFont.copyWith(
    fontWeight: FontWeight.w500,
    fontSize: 16,
    color: text,
    letterSpacing: -0.1,
  );

  // Private constructor to prevent instantiation
  DesignConstants._();
}
