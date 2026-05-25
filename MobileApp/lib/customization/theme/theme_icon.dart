import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/customization/customization_service.dart';
import 'package:mobile_app/customization/service_locator.dart';

/// App-agnostic icon resolver + renderer. Mirrors `ThemeImage`: looks up a
/// slot id in the loaded customization and, when an override SVG exists,
/// draws it (monochrome, tinted); otherwise it draws the bundled
/// `Symbols.*_sharp` fallback. With no customization at all (DI not set up,
/// nothing loaded, slot absent, or empty URL) it renders the fallback
/// directly — so the app still works with zero backend (the white-label
/// resilience property). Never throws.
///
/// Unlike `ThemeImage` (which only resolves a provider), icons need a render
/// step — `SvgPicture.network` with a placeholder — so the rendering lives
/// here as [widget] rather than in a separate widget class.
///
/// Use for theme/brand icons (nav tabs, brand affordances). Plain
/// structural `Icon(Symbols.…)` that will never be themed per-tenant can
/// stay as-is.
class ThemeIcon {
  // Private constructor to prevent instantiation.
  ThemeIcon._();

  /// The customization override SVG URL for [slot], or `null` when no
  /// customization applies to it.
  static String? svgUrl(String slot) {
    if (!getIt.isRegistered<CustomizationService>()) return null;
    final service = getIt<CustomizationService>();
    final raw = service.current?.icons[slot] ?? '';
    if (raw.isEmpty) return null;
    return service.resolveImageUrl(raw);
  }

  /// Renders the overridable icon for [slot]: the tenant SVG when present
  /// (tinted, showing [fallback] while it loads or if it fails), else the
  /// bundled [fallback] `Symbols.*_sharp`.
  ///
  /// [color] tints both the override SVG and the fallback symbol; it
  /// defaults to the ambient `IconTheme` colour, then `DesignConstants.text`.
  /// [weight] is the Material Symbol weight (defaults to
  /// `DesignConstants.iconWeight`).
  static Widget widget(
    BuildContext context, {
    required String slot,
    required IconData fallback,
    double size = DesignConstants.iconSizeMd,
    Color? color,
    double? weight,
  }) {
    final tint = color ?? IconTheme.of(context).color ?? DesignConstants.text;
    final fallbackIcon = Icon(
      fallback,
      size: size,
      color: tint,
      weight: weight ?? DesignConstants.iconWeight,
    );

    final url = svgUrl(slot);
    if (url == null) return fallbackIcon;

    return SvgPicture.network(
      url,
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(tint, BlendMode.srcIn),
      placeholderBuilder: (_) => fallbackIcon,
    );
  }
}
