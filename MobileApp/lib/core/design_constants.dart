import 'package:flutter/material.dart';

import 'package:mobile_app/core/app_slots.dart';
import 'package:mobile_app/customization/brand_color.dart';
import 'package:mobile_app/customization/brand_derivation.dart';
import 'package:mobile_app/customization/brand_font.dart';
import 'package:mobile_app/customization/data/models/color_mode.dart';

class DesignConstants {
  // Private constructor to prevent instantiation
  DesignConstants._();

  // ===========================================================
  // CombatDen verbatim fallbacks (used when no customization is
  // loaded). These exact values reproduce the bundled dark
  // CombatDen palette so an unbranded build still ships a sane
  // look.
  // ===========================================================
  static const Color _fallbackPrimary = Color(0xFFFF6C2D);
  static const Color _fallbackBackground = Color(0xFF121619);
  static const Color _fallbackText = Color(0xFFF4F3EE);
  static const Color _fallbackAccent = Color(0xFFE1B75C);
  static const String _fallbackFontFamily = 'Jura';

  /// Whether the resolved canvas is light, from the loaded
  /// customization's `color_set.mode`. When no customization is
  /// loaded this defaults to dark, matching the bundled const
  /// CombatDen palette (its `backgroundColor` fallback is also
  /// dark) so Material chrome and canvas stay consistent until a
  /// customization loads. Surface tokens (card/popup/divider) do
  /// NOT use this — they are sourced directly from the wire's
  /// flat palette; this only drives Material's discrete
  /// light/dark `ColorScheme` in `AppTheme.forCanvas()`.
  static bool get isLightCanvas =>
      BrandColor.mode(fallback: ColorMode.dark).isLight;

  // === Brand colours (base slots) ===
  // Resolved live from the customization engine via BrandColor;
  // the const fallback is the CombatDen palette, used verbatim
  // when no customization is loaded.
  static Color get primaryColor => BrandColor.color(
    CombatDenSlots.primary,
    fallback: _fallbackPrimary,
  );

  static Color get backgroundColor => BrandColor.color(
    CombatDenSlots.background,
    fallback: _fallbackBackground,
  );

  static Color get text => BrandColor.color(
    CombatDenSlots.text,
    fallback: _fallbackText,
  );

  /// Secondary brand accent — the SELECTION / active-state colour.
  /// Marks "where you are" (active nav item, active timeframe pill,
  /// active tab), distinct from `primaryColor` which marks agency
  /// ("what to tap").
  static Color get accent => BrandColor.color(
    CombatDenSlots.accent,
    fallback: _fallbackAccent,
  );

  // === Derived tokens (sourced from each base slot's derivations) ===
  // The service centralises the math: every base slot ships seven
  // pre-computed variants (`second`/`third`/`card`/`popup`/`dark`/
  // `light`/`regular_text`). The local fallback expressions only fire
  // when the derivation is absent.
  static Color get primaryColor50 => BrandColor.color(
    CombatDenSlots.primary,
    derivation: BrandDerivation.third,
    fallback: _fallbackPrimary.withValues(alpha: 0.5),
  );

  /// Darker primary — tracks the branded primary on the wire.
  static Color get darkPrimary => BrandColor.color(
    CombatDenSlots.primary,
    derivation: BrandDerivation.dark,
    fallback: _darkPrimaryFallback,
  );

  static Color get _darkPrimaryFallback {
    final hsl = HSLColor.fromColor(_fallbackPrimary);
    return hsl
        .withLightness((hsl.lightness * 0.42).clamp(0.0, 1.0))
        .toColor();
  }

  /// A primary-tinted surface (brand card), mode-agnostic: 9% alpha
  /// over the canvas, sourced from `primary.card`.
  static Color get primaryCard => BrandColor.color(
    CombatDenSlots.primary,
    derivation: BrandDerivation.card,
    fallback: _fallbackPrimary.withValues(alpha: 0.09),
  );

  /// Readable colour for text/labels painted ON the primary fill
  /// (primary buttons, the reward price tag). Sourced from
  /// `primary.regular_text`: the pipeline picks the body text colour
  /// when it clears WCAG AA on the primary fill, otherwise the
  /// background colour. Falls back to the body text colour.
  static Color get primaryButtonText => BrandColor.color(
    CombatDenSlots.primary,
    derivation: BrandDerivation.regularText,
    fallback: _fallbackText,
  );

  static Color get text2nd => BrandColor.color(
    CombatDenSlots.text,
    derivation: BrandDerivation.second,
    fallback: _fallbackText.withValues(alpha: 0.75),
  );

  static Color get text3rd => BrandColor.color(
    CombatDenSlots.text,
    derivation: BrandDerivation.third,
    fallback: _fallbackText.withValues(alpha: 0.50),
  );

  /// Elevated surface tint — translucent so layered surfaces
  /// auto-lighten by compositing over whatever sits behind them.
  static Color get card => BrandColor.paletteEntry(
    'card',
    fallback: _liveSurfaceFallback,
  );

  /// Opaque modal surface — content cannot bleed through.
  static Color get popup => BrandColor.paletteEntry(
    'popup',
    fallback: Color.alphaBlend(_liveSurfaceFallback, backgroundColor),
  );

  /// A separating line — keyed to `text` with alpha rising as the
  /// background lightens.
  static Color get divider => BrandColor.paletteEntry(
    'divider',
    fallback: text.withValues(
      alpha: (0.10 + 0.10 * HSLColor.fromColor(backgroundColor).lightness)
          .clamp(0.10, 0.22),
    ),
  );

  /// Live-background-aware white veil. Heavier as the background
  /// gets lighter (a near-white canvas needs more to read as
  /// raised; a near-black one needs almost none). Used only as
  /// the fallback for `card` / `popup` when the wire's palette is
  /// missing those tokens.
  static Color get _liveSurfaceFallback {
    final l = HSLColor.fromColor(backgroundColor).lightness; // 0..1
    final alpha = (0.06 + 0.5 * (l / 0.9));
    return Colors.white.withValues(alpha: alpha);
  }

  // === Status / semantic colours (NOT brandable) ===
  static const Color hyperlink = Color(0xFF83C7FF);
  static const Color goodGreen = Color(0xFF74F394);
  static const Color okYellow = Color(0xFFCCCE44);
  static const Color badRed = Color(0xFFF94A4D);

  static final Color yellowDark = Color(0xFF83852F).withValues(alpha: 0.25);
  static final Color greenDark = Color(0xFF0E7A29).withValues(alpha: 0.25);
  static final Color purpleDark = Color(0xFF744373).withValues(alpha: 0.25);
  static final Color blueDark = Color(0xFF425E67).withValues(alpha: 0.25);
  static final Color redDark = Color(0xFF6D2C22).withValues(alpha: 0.25);

  // === Layout / sizing constants ===
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
  static const double sideNavWidth = 100.0;
  static const double tableRowHeight = 35.0;

  // ===========================================================
  // Typography — two fonts. `displayFont` is reserved for hero
  // numerals / celebration moments (big1 / big1_5 / big2). Every
  // running-UI style (h1..h3, p variants) uses `bodyFont`.
  // ===========================================================
  // These are getters, not `static final`, on purpose: a `static final`
  // TextStyle would bake in `color: text` (and the resolved font) ONCE,
  // at first access, and never pick up a live style switch. As getters
  // they re-resolve `text` / `bodyFont` / `displayFont` on every read, so
  // headings re-theme with the rest of the app when the customization
  // changes.
  static TextStyle get displayFont => BrandFont.style(
    CombatDenSlots.fontDisplay,
    fallbackFamily: _fallbackFontFamily,
  );

  static TextStyle get bodyFont => BrandFont.style(
    CombatDenSlots.fontBody,
    fallbackFamily: _fallbackFontFamily,
  );

  /// H1 text style
  static TextStyle get h1 => bodyFont.copyWith(
    fontWeight: FontWeight.w700,
    fontSize: 24,
    color: text,
    letterSpacing: -0.02,
  );

  static TextStyle get h1Regular => h1.copyWith(fontWeight: FontWeight.w500);

  /// H2 text style
  static TextStyle get h2 => bodyFont.copyWith(
    fontWeight: FontWeight.w600,
    fontSize: 16,
    color: text,
    letterSpacing: 0,
  );

  static TextStyle get h2Regular => h2.copyWith(
    fontWeight: FontWeight.w400,
    letterSpacing: 0.03,
  );

  static TextStyle get h2Bold => h2.copyWith(fontWeight: FontWeight.w700);

  /// H3 text style
  static TextStyle get h3 => bodyFont.copyWith(
    fontWeight: FontWeight.w600,
    fontSize: 13,
    color: text,
    letterSpacing: 0,
  );

  /// Paragraph text style
  static TextStyle get p => bodyFont.copyWith(
    fontWeight: FontWeight.w400,
    fontSize: 12,
    color: text,
    letterSpacing: 0.03,
  );

  static TextStyle get pBig => p.copyWith(fontSize: 16);
  static TextStyle get pSmall => p.copyWith(fontSize: 11);

  /// Hero numerals — celebration moments only.
  static TextStyle get big1 => displayFont.copyWith(
    fontWeight: FontWeight.w600,
    fontSize: 160,
    color: text,
  );

  static TextStyle get big1_5 => displayFont.copyWith(
    fontWeight: FontWeight.w600,
    fontSize: 64,
    color: text,
  );

  static TextStyle get big2 => displayFont.copyWith(
    fontWeight: FontWeight.w600,
    fontSize: 32,
    color: text,
  );
}
