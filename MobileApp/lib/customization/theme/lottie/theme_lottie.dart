import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/customization/theme/theme_color.dart';
import 'package:mobile_app/customization/customization_service.dart';
import 'package:mobile_app/customization/data/models/lottie_override.dart';
import 'package:mobile_app/customization/service_locator.dart';

/// The base CustomizationService-overridable Lottie widget for [slot].
///
/// If the loaded tenant customization supplies a preset for [slot] it
/// plays that (fetched over the network), recolouring each named region to
/// its mapped palette role, and falls back to [fallbackAsset] on load
/// failure. With no customization at all it plays [fallbackAsset] directly,
/// tinted with the brand primary (the existing bundled-asset behaviour).
/// The engine never owns the fallback, so the app still animates with zero
/// backend (the white-label resilience property).
///
/// [controller] / [onLoaded] are forwarded to both paths so a call site
/// can drive the animation (set duration on load, play, listen for
/// completion) regardless of whether an override is active.
///
/// `ThemeRevealLottie` builds on this widget, adding the composite-at-frame
/// behaviour it doesn't do.
class ThemeLottie extends StatelessWidget {
  const ThemeLottie({
    super.key,
    required this.slot,
    required this.fallbackAsset,
    this.controller,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.onLoaded,
  });

  /// The customization override for [slot] (URL absolutised), or `null`
  /// when no customization applies to it (DI not set up, nothing loaded,
  /// slot absent, or empty URL). Never throws. A `null` return means "play
  /// your bundled `.json`".
  static LottieOverride? resolve(String slot) {
    if (!getIt.isRegistered<CustomizationService>()) return null;
    final service = getIt<CustomizationService>();
    final override = service.current?.lotties[slot];
    if (override == null || override.url.isEmpty) return null;
    return LottieOverride(
      url: service.resolveImageUrl(override.url),
      regionRoles: override.regionRoles,
      reveals: override.reveals,
      insertionPoint: override.insertionPoint,
    );
  }

  /// Customization slot id (see `CombatDenSlots`).
  final String slot;

  /// Bundled `.json` played when [slot] has no override (or the override
  /// fails to load).
  final String fallbackAsset;

  final AnimationController? controller;
  final double? width;
  final double? height;
  final BoxFit fit;
  final void Function(LottieComposition)? onLoaded;

  @override
  Widget build(BuildContext context) {
    final override = resolve(slot);
    if (override == null) return _asset();
    return Lottie.network(
      override.url,
      controller: controller,
      width: width,
      height: height,
      fit: fit,
      onLoaded: onLoaded,
      delegates: _regionDelegates(override.regionRoles),
      errorBuilder: (_, _, _) => _asset(),
    );
  }

  Widget _asset() {
    return Lottie.asset(
      fallbackAsset,
      controller: controller,
      width: width,
      height: height,
      fit: fit,
      onLoaded: onLoaded,
      delegates: _wildcardTint(),
    );
  }

  /// Tint everything with the brand primary — the legacy `['**']`
  /// behaviour, used for the bundled fallback and when an override carries
  /// no recolour data.
  LottieDelegates _wildcardTint() {
    final brand = DesignConstants.primaryColor;
    return LottieDelegates(
      values: [
        ValueDelegate.color(const ['**'], value: brand),
        ValueDelegate.strokeColor(const ['**'], value: brand),
      ],
    );
  }

  /// Per-region recolour: each layer name is tinted to its mapped palette
  /// role, resolved against the live palette via `ThemeColor.token` (which
  /// covers both derived tokens and base roles). An empty map degrades to
  /// the wildcard tint.
  LottieDelegates _regionDelegates(Map<String, String> regionRoles) {
    if (regionRoles.isEmpty) return _wildcardTint();
    final brand = DesignConstants.primaryColor;
    final values = <ValueDelegate>[];
    regionRoles.forEach((region, roleKey) {
      final color = ThemeColor.token(roleKey, fallback: brand);
      values
        ..add(ValueDelegate.color([region, '**'], value: color))
        ..add(ValueDelegate.strokeColor([region, '**'], value: color));
    });
    return LottieDelegates(values: values);
  }
}
