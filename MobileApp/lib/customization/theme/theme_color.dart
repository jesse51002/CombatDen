import 'package:flutter/material.dart';

import 'package:mobile_app/customization/customization_service.dart';
import 'package:mobile_app/customization/data/models/color_mode.dart';
import 'package:mobile_app/customization/service_locator.dart';

/// App-agnostic colour resolver. Looks up a slot id in the
/// loaded customization, returning [fallback] when no
/// customization is loaded, the slot is absent/unparseable, or
/// DI is not set up (tests). Never throws. Used inside
/// `DesignConstants`, so every `DesignConstants.X` call site is
/// branded with zero plumbing.
class ThemeColor {
  // Private constructor to prevent instantiation
  ThemeColor._();

  /// Resolves a colour slot. With no [derivation], returns the
  /// base colour. With [derivation] set (e.g.
  /// `ThemeDerivation.card`), returns that pre-computed variant
  /// from `colors[key].derivations`. Returns [fallback] on any
  /// miss — never throws.
  static Color color(
    String key, {
    String? derivation,
    required Color fallback,
  }) {
    if (!getIt.isRegistered<CustomizationService>()) {
      return fallback;
    }
    final slot = getIt<CustomizationService>().current?.colors[key];
    if (slot == null) return fallback;
    if (derivation == null) {
      return slot.color ?? fallback;
    }
    return slot.derivations[derivation] ?? fallback;
  }

  /// Looks up an entry on the loaded customization's flat
  /// `color_set.palette` — every `<slot>_<derivation>` pair the
  /// service pre-computes (e.g. `primary_dark`, `background_popup`)
  /// plus the shared surface tokens (`card`, `popup`, `divider`).
  /// Returns [fallback] when no customization is loaded, the entry
  /// is absent, or DI is not set up.
  ///
  /// For a base-slot + derivation pair, prefer
  /// `ThemeColor.color(slot, derivation: ...)` — that goes through
  /// the typed slot map and is symmetric with the rest of the
  /// resolver. Use [paletteEntry] only for the orphan tokens
  /// (`card` / `popup` / `divider`) which have no base slot.
  static Color paletteEntry(
    String key, {
    required Color fallback,
  }) {
    if (!getIt.isRegistered<CustomizationService>()) {
      return fallback;
    }
    return getIt<CustomizationService>().current?.palette[key] ?? fallback;
  }

  /// Resolves an arbitrary palette ROLE key to a colour, checking both
  /// stores: the flat [palette] (derived/shared tokens like
  /// `primary_third`, `card`) AND the typed [colors] map (base roles like
  /// `primary`, `accent`, which are NOT flattened into the palette).
  /// Returns [fallback] on any miss — never throws.
  ///
  /// This is the resolver for keys whose store isn't known up front — e.g.
  /// a lottie `region_roles` value, which the recolour LLM may set to
  /// either a base role or a derived key. For known base-slot lookups use
  /// [color]; for known orphan tokens use [paletteEntry].
  static Color token(
    String key, {
    required Color fallback,
  }) {
    if (!getIt.isRegistered<CustomizationService>()) {
      return fallback;
    }
    final current = getIt<CustomizationService>().current;
    if (current == null) return fallback;
    return current.palette[key] ?? current.colors[key]?.color ?? fallback;
  }

  /// The loaded customization's light/dark mode. Same contract as
  /// [color]: returns [fallback] when no customization is loaded or
  /// DI is not set up (tests). Never throws.
  static ColorMode mode({
    required ColorMode fallback,
  }) {
    if (!getIt.isRegistered<CustomizationService>()) {
      return fallback;
    }
    return getIt<CustomizationService>().current?.colorMode ?? fallback;
  }
}
