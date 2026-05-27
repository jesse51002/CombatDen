import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import 'package:customization_engine/customization_service.dart';
import 'package:customization_engine/data/models/lottie_override.dart';
import 'package:customization_engine/service_locator.dart';

/// The base CustomizationService-overridable Lottie widget for [slot].
///
/// If the loaded tenant customization supplies a preset for [slot] it plays
/// that (fetched over the network) and falls back to [fallbackAsset] on load
/// failure. With no customization at all it plays [fallbackAsset] directly.
/// The colour is **baked into the served file** by the pipeline, so this
/// widget never recolours — it just plays the animation. The engine never
/// owns the fallback, so the app still animates with zero backend (the
/// white-label resilience property).
///
/// [controller] / [onLoaded] are forwarded to both paths so a call site can
/// drive the animation (play, listen for completion) regardless of whether
/// an override is active. When an override carries a `speed`, this widget
/// sets `controller.duration` to the composition duration scaled by it on
/// load (before invoking the caller's [onLoaded]); the caller only needs to
/// `forward()`.
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
      speed: override.speed,
      reveals: override.reveals,
      insertionPoint: override.insertionPoint,
      holdSeconds: override.holdSeconds,
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
      onLoaded: (composition) => _onLoaded(composition, override.speed),
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
      // Bundled fallback has no preset metadata: play it at its authored
      // speed and colours.
      onLoaded: (composition) => _onLoaded(composition, 1.0),
    );
  }

  /// Scale [controller]'s duration by [speed] (2.0 => half the time), then
  /// hand the loaded composition to the caller's [onLoaded] (which only has
  /// to `forward()` / read frames). With no controller this is just the
  /// passthrough.
  void _onLoaded(LottieComposition composition, double speed) {
    final c = controller;
    if (c != null) {
      c.duration = composition.duration * (1.0 / speed);
    }
    onLoaded?.call(composition);
  }
}
