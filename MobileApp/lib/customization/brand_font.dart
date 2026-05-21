import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:mobile_app/customization/customization_service.dart';
import 'package:mobile_app/customization/service_locator.dart';

/// App-agnostic font resolver. Looks up a slot id in the loaded
/// customization, hands the resolved Google Fonts family to
/// `GoogleFonts.getFont(...)`, and returns a `TextStyle` ready for
/// `.copyWith(...)`. Falls back to [fallbackFamily] when no
/// customization is loaded, the slot is absent, or DI is not set up
/// (tests). Never throws — a family the `google_fonts` package
/// can't resolve degrades to a bare system-font `TextStyle`.
class BrandFont {
  // Private constructor to prevent instantiation
  BrandFont._();

  static TextStyle style(
    String slot, {
    required String fallbackFamily,
  }) {
    final family = _resolveFamily(slot) ?? fallbackFamily;
    try {
      return GoogleFonts.getFont(family);
    } catch (_) {
      // Family not in the google_fonts package catalog: degrade to
      // the system default rather than crash the text style.
      return const TextStyle();
    }
  }

  static String? _resolveFamily(String slot) {
    if (!getIt.isRegistered<CustomizationService>()) return null;
    final family = getIt<CustomizationService>().current?.fonts[slot];
    if (family == null || family.isEmpty) return null;
    return family;
  }
}
