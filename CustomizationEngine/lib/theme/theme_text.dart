import 'package:customization_engine/customization_service.dart';
import 'package:customization_engine/service_locator.dart';

/// App-agnostic text resolver. Looks up a slot id in the loaded
/// customization's `text_set` and returns the brand-rewritten copy
/// (e.g. "Dance with us" instead of "Reserve your spot"). Falls
/// back to [fallback] when no customization is loaded, the slot is
/// absent or empty, or DI is not set up (tests). Never throws.
class ThemeText {
  // Private constructor to prevent instantiation
  ThemeText._();

  static String value(
    String slot, {
    required String fallback,
  }) {
    if (!getIt.isRegistered<CustomizationService>()) return fallback;
    final resolved = getIt<CustomizationService>().current?.texts[slot];
    if (resolved == null || resolved.isEmpty) return fallback;
    return resolved;
  }

  /// The loaded theme's [designName] — this run's design/style name
  /// (e.g. "Warm Ash Cream"), a top-level field rather than a text slot
  /// (mirrors `ThemeColor.colorMode`). Falls back to [fallback] when no
  /// customization is loaded, the name is empty, or DI is not set up
  /// (tests). Never throws.
  static String designName({required String fallback}) {
    if (!getIt.isRegistered<CustomizationService>()) return fallback;
    final name = getIt<CustomizationService>().current?.designName;
    if (name == null || name.isEmpty) return fallback;
    return name;
  }
}
