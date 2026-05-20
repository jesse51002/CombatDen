import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:mobile_app/core/app_slots.dart';
import 'package:mobile_app/customization/brand_color.dart';
import 'package:mobile_app/customization/data/models/color_mode.dart';

class DesignConstants {
  // Private constructor to prevent instantiation
  DesignConstants._();

  /// Whether the resolved canvas is light, from the loaded
  /// customization's `color_set.mode`. When no customization is
  /// loaded this defaults to dark, matching the bundled const
  /// CombatDen palette (its `backgroundColor` fallback is also
  /// dark) so Material chrome and canvas stay consistent until a
  /// customization loads. Surface tokens (card/popup/divider) do
  /// NOT use this — they are automatic from the background's HSL
  /// lightness; this only drives Material's discrete light/dark
  /// `ColorScheme` in `AppTheme.forCanvas()`.
  static bool get isLightCanvas =>
      BrandColor.mode(fallback: ColorMode.dark).isLight;

  // === Brand colours ===
  // Resolved live from the customization engine via BrandColor;
  // the const fallback is the CombatDen palette, used verbatim
  // when no customization is loaded. Call sites keep using
  // `DesignConstants.X` — no plumbing anywhere in the app.
  static Color get primaryColor => BrandColor.color(
    CombatDenSlots.primary,
    fallback: const Color(0xFFFF6C2D),
  );
  static Color get primaryColor50 => primaryColor.withValues(alpha: 0.5);
  static Color get primaryColor25 => primaryColor.withValues(alpha: 0.25);
  static Color get primaryColor10 => primaryColor.withValues(alpha: 0.1);

  /// Darker primary — derived so it tracks the branded primary.
  static Color get darkPrimary {
    final hsl = HSLColor.fromColor(primaryColor);
    return hsl.withLightness((hsl.lightness * 0.42).clamp(0.0, 1.0)).toColor();
  }

  /// Secondary brand accent — the SELECTION / active-state colour.
  /// Marks "where you are" (active nav item, active timeframe pill,
  /// active tab), distinct from `primaryColor` which marks agency
  /// ("what to tap"). The const fallback is the CombatDen baseline
  /// (muted "Premium Gold", the exact sRGB of `oklch(80% 0.12 85)`
  /// emitted for the served design) so offline rendering matches
  /// the live palette.
  static Color get accent => BrandColor.color(
    CombatDenSlots.accent,
    fallback: const Color(0xFFE1B75C),
  );

  // === Brand colours (resolved via the customization engine) ===
  static Color get backgroundColor => BrandColor.color(
    CombatDenSlots.background,
    fallback: const Color(0xFF121619),
  );

  static Color get text =>
      BrandColor.color(CombatDenSlots.text, fallback: const Color(0xFFF4F3EE));
  static Color get text2nd => text.withValues(alpha: 0.75);
  static Color get text3rd => text.withValues(alpha: 0.50);

  // Elevation: a translucent white veil over the resolved canvas.
  // Heavier as the background gets lighter (a near-white canvas
  // needs more to read as raised; a near-black one needs almost
  // none). Translucent so layered surfaces auto-lighten by
  // compositing over whatever sits behind them.
  static double get _elevationAlpha {
    final l = HSLColor.fromColor(backgroundColor).lightness; // 0..1
    return (0.06 + 0.5 * (l / 0.9));
  }

  static Color get card => Colors.white.withValues(alpha: _elevationAlpha);

  // Opaque: a modal must not let content bleed through.
  static Color get popup => Color.alphaBlend(
    Colors.white.withValues(alpha: _elevationAlpha),
    backgroundColor,
  );

  /// INTERIM, best-effort. A primary-tinted surface (brand card),
  /// mode-aware: deep on a dark canvas, pale on a light one — same
  /// lightness-shift idea as the white-veil `card`, keyed to
  /// `primaryColor`. Foreground-text contrast (incl.
  /// `primaryColor`-as-text) is NOT solved here; this whole surface
  /// derivation is slated to move into the CustomizationService
  /// pipeline so it generalises across apps (see that repo's
  /// README TODO). Until then this is a deliberately simple stand-in.
  static Color get primaryCard {
    final hsl = HSLColor.fromColor(primaryColor);
    final l = isLightCanvas
        ? hsl.lightness + (1 - hsl.lightness) * 0.82
        : hsl.lightness * 0.30;
    return hsl.withLightness(l.clamp(0.0, 1.0)).toColor();
  }

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

  // A separating line needs contrast *against* the surface, not
  // elevation above it: keyed to `text` (auto-flips per preset —
  // bone-light on a dark canvas, slate-dark on a light one), with
  // alpha rising as the background lightens so it stays automatic.
  static Color get divider => text.withValues(
    alpha: (0.10 + 0.10 * HSLColor.fromColor(backgroundColor).lightness).clamp(
      0.10,
      0.22,
    ),
  );
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

  static final TextStyle h2Regular = h2.copyWith(
    fontWeight: FontWeight.w400,
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
}
