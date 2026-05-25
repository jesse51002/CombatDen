import 'package:mobile_app/customization/customization_service.dart';
import 'package:mobile_app/customization/data/models/lottie_override.dart';
import 'package:mobile_app/customization/service_locator.dart';

/// App-agnostic lottie resolver. Mirrors `BrandImage`: looks up a slot id
/// in the loaded customization and returns its [LottieOverride] with the
/// preset URL already absolutised, or `null` when there is no
/// customization (DI not set up, nothing loaded, slot absent, or empty
/// URL). Never throws.
///
/// Owns NO fallback: a `null` return means "play your bundled `.json`".
/// See `BrandedLottie` for the app-side widget that pairs this with the
/// bundled-asset fallback and applies the region→role recolour.
class BrandLottie {
  // Private constructor to prevent instantiation.
  BrandLottie._();

  /// The customization override for [slot] (URL absolutised), or `null`
  /// when no customization applies to it.
  static LottieOverride? of(String slot) {
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
}
