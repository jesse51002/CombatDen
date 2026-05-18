import 'package:flutter/material.dart';

import 'package:mobile_app/customization/service_locator.dart';
import 'package:mobile_app/customization/customization_service.dart';

/// App-agnostic colour resolver. Looks up a slot id in the
/// loaded customization, returning [fallback] when no
/// customization is loaded, the slot is absent/unparseable, or
/// DI is not set up (tests). Never throws. Used inside
/// `DesignConstants`, so every `DesignConstants.X` call site is
/// branded with zero plumbing.
class BrandColor {
  // Private constructor to prevent instantiation
  BrandColor._();

  static Color color(
    String key, {
    required Color fallback,
  }) {
    if (!getIt.isRegistered<CustomizationService>()) {
      return fallback;
    }
    final resolved = getIt<CustomizationService>()
        .current
        ?.colors[key]
        ?.color;
    return resolved ?? fallback;
  }
}
