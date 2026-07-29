import 'package:theme_flutter/customization_service.dart';
import 'package:theme_flutter/data/models/customization_format.dart';
import 'package:theme_flutter/service_locator.dart';

/// App-agnostic layout/motion format resolver.
///
/// Looks a slot id up in the loaded customization's `format_set` and
/// returns the arrangement the generator chose, e.g. `home_format` ->
/// `nextUpHero`. Falls back to [fallback] when no customization is
/// loaded, the slot is absent, or DI is not set up (tests). Never
/// throws.
///
/// The engine deliberately does NOT validate the value against any
/// vocabulary: it does not know the app's formats, and the app parses
/// the string against its own enum with its shipped arrangement as the
/// fallback. That way a service running ahead of a client degrades to
/// the shipped look instead of breaking a screen.
class ThemeFormat {
  // Private constructor to prevent instantiation
  ThemeFormat._();

  /// The chosen arrangement for [slot], or [fallback].
  static String value(String slot, {required String fallback}) =>
      entry(slot)?.value ?? fallback;

  /// The full entry, including the generator's rationale. Null when the
  /// slot is absent — used by review surfaces that show *why* a screen
  /// was arranged this way.
  static ThemeFormatValue? entry(String slot) {
    if (!getIt.isRegistered<ThemeService>()) return null;
    final resolved = getIt<ThemeService>().current?.formats[slot];
    if (resolved == null || resolved.value.isEmpty) return null;
    return resolved;
  }
}
