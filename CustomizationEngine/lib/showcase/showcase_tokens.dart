import 'package:flutter/material.dart';

import 'package:customization_engine/showcase/showcase_slots.dart';
import 'package:customization_engine/theme/theme_color.dart';
import 'package:customization_engine/theme/theme_derivation.dart';
import 'package:customization_engine/theme/theme_font.dart';
import 'package:customization_engine/data/models/color_mode.dart';

/// Design tokens for the engine's **showcase** screens — a faithful mirror
/// of MobileApp's `DesignConstants`, re-themed LIVE by the loaded
/// customization's brand colours/fonts. The showcase screens are exact
/// visual clones of the member app, so this carries the member app's full
/// token surface (colours, derivations, radii, spacing, icon sizes,
/// typography ramp) using `ShowcaseSlots` for the slot ids.
///
/// DELIBERATELY NOT named `DesignConstants` and must NOT be merged with
/// either consuming app's `DesignConstants`:
///   * MobileApp's `DesignConstants` is the member app's own surface.
///   * AppManagement's `DesignConstants` is a separate forked LIGHT theme.
/// The showcase is a self-contained island painting the *member* app, so it
/// owns its tokens here in the shared package, depending on neither app.
class ShowcaseTokens {
  ShowcaseTokens._();

  // CombatDen verbatim fallbacks — used only when no customization loads.
  static const Color _fallbackPrimary = Color(0xFFFF6C2D);
  static const Color _fallbackBackground = Color(0xFF121619);
  static const Color _fallbackText = Color(0xFFF4F3EE);
  static const Color _fallbackAccent = Color(0xFFE1B75C);
  static const String _fallbackFontFamily = 'Jura';

  /// Whether the resolved canvas is light, from the customization's mode.
  static bool get isLightCanvas =>
      ThemeColor.mode(fallback: ColorMode.dark).isLight;

  // === Brand colours (resolved live) ===
  static Color get primaryColor =>
      ThemeColor.color(ShowcaseSlots.primary, fallback: _fallbackPrimary);

  static Color get backgroundColor =>
      ThemeColor.color(ShowcaseSlots.background, fallback: _fallbackBackground);

  static Color get text =>
      ThemeColor.color(ShowcaseSlots.text, fallback: _fallbackText);

  /// Selection / active-state accent.
  static Color get accent =>
      ThemeColor.color(ShowcaseSlots.accent, fallback: _fallbackAccent);

  // === Derived tokens ===
  static Color get primaryColor50 => ThemeColor.color(
    ShowcaseSlots.primary,
    derivation: ThemeDerivation.third,
    fallback: _fallbackPrimary.withValues(alpha: 0.5),
  );

  static Color get darkPrimary => ThemeColor.color(
    ShowcaseSlots.primary,
    derivation: ThemeDerivation.dark,
    fallback: _darkPrimaryFallback,
  );

  static Color get _darkPrimaryFallback {
    final hsl = HSLColor.fromColor(_fallbackPrimary);
    return hsl.withLightness((hsl.lightness * 0.42).clamp(0.0, 1.0)).toColor();
  }

  static Color get primaryCard => ThemeColor.color(
    ShowcaseSlots.primary,
    derivation: ThemeDerivation.card,
    fallback: _fallbackPrimary.withValues(alpha: 0.09),
  );

  static Color get primaryButtonText => ThemeColor.color(
    ShowcaseSlots.primary,
    derivation: ThemeDerivation.regularText,
    fallback: _fallbackText,
  );

  static Color get text2nd => ThemeColor.color(
    ShowcaseSlots.text,
    derivation: ThemeDerivation.second,
    fallback: _fallbackText.withValues(alpha: 0.75),
  );

  static Color get text3rd => ThemeColor.color(
    ShowcaseSlots.text,
    derivation: ThemeDerivation.third,
    fallback: _fallbackText.withValues(alpha: 0.50),
  );

  static Color get card =>
      ThemeColor.paletteEntry('card', fallback: _liveSurfaceFallback);

  static Color get popup => ThemeColor.paletteEntry(
    'popup',
    fallback: Color.alphaBlend(_liveSurfaceFallback, backgroundColor),
  );

  static Color get divider => ThemeColor.paletteEntry(
    'divider',
    fallback: text.withValues(
      alpha: (0.10 + 0.10 * HSLColor.fromColor(backgroundColor).lightness)
          .clamp(0.10, 0.22),
    ),
  );

  static Color get _liveSurfaceFallback {
    final l = HSLColor.fromColor(backgroundColor).lightness;
    final alpha = (0.06 + 0.5 * (l / 0.9));
    return Colors.white.withValues(alpha: alpha);
  }

  // === Status / semantic colours (NOT brandable) ===
  static const Color hyperlink = Color(0xFF83C7FF);
  static const Color goodGreen = Color(0xFF74F394);
  static const Color okYellow = Color(0xFFCCCE44);
  static const Color badRed = Color(0xFFF94A4D);

  // === Layout / sizing ===
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

  static const double buttonBorder = 2;
  static const double iconWeight = 300.0;
  static const double buttonBorderSize = 3.0;
  static const double screenHorizontalPadding = 16.0;

  // Icon sizes (T-shirt scale, 16 + 4x)
  static const double iconSizeXs = 16;
  static const double iconSizeSm = 20;
  static const double iconSizeMd = 24;
  static const double iconSizeLg = 28;
  static const double iconSizeXl = 32;
  static const double iconSize2xl = 36;

  static const double pillHeightSm = 24;
  static const double pillHeightMd = 30;
  static const double dividerThickness = 1;

  // === Typography (getters so they re-resolve / re-theme live) ===
  static TextStyle get displayFont => ThemeFont.style(
    ShowcaseSlots.fontDisplay,
    fallbackFamily: _fallbackFontFamily,
  );

  static TextStyle get bodyFont => ThemeFont.style(
    ShowcaseSlots.fontBody,
    fallbackFamily: _fallbackFontFamily,
  );

  static TextStyle get h1 => bodyFont.copyWith(
    fontWeight: FontWeight.w700,
    fontSize: 24,
    color: text,
    letterSpacing: -0.02,
  );

  static TextStyle get h1Regular => h1.copyWith(fontWeight: FontWeight.w500);

  static TextStyle get h2 => bodyFont.copyWith(
    fontWeight: FontWeight.w600,
    fontSize: 16,
    color: text,
    letterSpacing: 0,
  );

  static TextStyle get h2Regular =>
      h2.copyWith(fontWeight: FontWeight.w400, letterSpacing: 0.03);

  static TextStyle get h2Bold => h2.copyWith(fontWeight: FontWeight.w700);

  static TextStyle get h3 => bodyFont.copyWith(
    fontWeight: FontWeight.w600,
    fontSize: 13,
    color: text,
    letterSpacing: 0,
  );

  static TextStyle get p => bodyFont.copyWith(
    fontWeight: FontWeight.w400,
    fontSize: 12,
    color: text,
    letterSpacing: 0.03,
  );

  static TextStyle get pBig => p.copyWith(fontSize: 16);
  static TextStyle get pSmall => p.copyWith(fontSize: 11);

  // Hero numerals — celebration moments only.
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
