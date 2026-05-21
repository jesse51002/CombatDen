import 'package:mobile_app/customization/customization_service.dart';
import 'package:mobile_app/customization/service_locator.dart';

/// App-agnostic text resolver. Looks up a slot id in the loaded
/// customization's `text_set` and returns the brand-rewritten copy
/// (e.g. "Dance with us" instead of "Reserve your spot"). Falls
/// back to [fallback] when no customization is loaded, the slot is
/// absent or empty, or DI is not set up (tests). Never throws.
class BrandText {
  // Private constructor to prevent instantiation
  BrandText._();

  static String value(
    String slot, {
    required String fallback,
  }) {
    if (!getIt.isRegistered<CustomizationService>()) return fallback;
    final resolved = getIt<CustomizationService>().current?.texts[slot];
    if (resolved == null || resolved.isEmpty) return fallback;
    return resolved;
  }
}
