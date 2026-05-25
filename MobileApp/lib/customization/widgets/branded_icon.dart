import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/customization/brand_icon.dart';

/// Renders a CustomizationService-overridable icon for [slot].
///
/// If the loaded tenant customization supplies an SVG for [slot] it draws
/// that (monochrome, tinted to [color]), showing [fallback] while it loads
/// or if it fails. With no customization at all it renders [fallback]
/// directly — the call site's `Symbols.*_sharp`. The engine never owns the
/// fallback, so the app still works with zero backend (the white-label
/// resilience property, same as `BrandedImage`).
///
/// Use for theme/brand icons (nav tabs, brand affordances). Plain
/// structural `Icon(Symbols.…)` that will never be themed per-tenant can
/// stay as-is.
class BrandedIcon extends StatelessWidget {
  const BrandedIcon({
    super.key,
    required this.slot,
    required this.fallback,
    this.size = DesignConstants.iconSizeMd,
    this.color,
    this.weight,
  });

  /// Customization slot id (see `CombatDenSlots`).
  final String slot;

  /// Material Symbol rendered when [slot] has no override (or its SVG is
  /// still loading / failed to load).
  final IconData fallback;

  final double size;

  /// Tint applied to both the override SVG and the fallback symbol.
  /// Defaults to the ambient `IconTheme` colour, then `DesignConstants.text`.
  final Color? color;

  /// Material Symbol weight; defaults to `DesignConstants.iconWeight`.
  final double? weight;

  @override
  Widget build(BuildContext context) {
    final tint =
        color ?? IconTheme.of(context).color ?? DesignConstants.text;
    final fallbackIcon = Icon(
      fallback,
      size: size,
      color: tint,
      weight: weight ?? DesignConstants.iconWeight,
    );

    final url = BrandIcon.svgUrl(slot);
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
