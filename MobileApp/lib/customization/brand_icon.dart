import 'package:mobile_app/customization/customization_service.dart';
import 'package:mobile_app/customization/service_locator.dart';

/// App-agnostic icon resolver. Mirrors `BrandImage`: looks up a slot id in
/// the loaded customization and returns the absolute URL of the override
/// SVG, or `null` when there is no customization (DI not set up, nothing
/// loaded, slot absent, or empty URL). Never throws.
///
/// Like the rest of the engine it owns NO fallback: a `null` return means
/// "render your bundled `Symbols.*_sharp`". See `BrandedIcon` for the
/// app-side widget that pairs this with that Material Symbol fallback.
///
/// Icons are monochrome (`currentColor`), so the colour is applied at the
/// render site, not here — this only resolves *which* SVG to draw.
class BrandIcon {
  // Private constructor to prevent instantiation.
  BrandIcon._();

  /// The customization override SVG URL for [slot], or `null` when no
  /// customization applies to it.
  static String? svgUrl(String slot) {
    if (!getIt.isRegistered<CustomizationService>()) return null;
    final service = getIt<CustomizationService>();
    final raw = service.current?.icons[slot] ?? '';
    if (raw.isEmpty) return null;
    return service.resolveImageUrl(raw);
  }
}
