import 'package:flutter/material.dart';

/// The few non-brand constants the engine's own resolvers need as
/// last-resort defaults, so the package depends on NEITHER consuming app's
/// `DesignConstants`. These are only fallbacks: every call site that has a
/// real value (icon size/weight/colour, a loaded brand colour) passes or
/// resolves it, and these never fire then.
///
/// Brand colours still resolve LIVE from the loaded customization via
/// `ThemeColor.token(...)`; the values here are just the const fallbacks
/// used when nothing is loaded (the white-label resilience property). They
/// mirror the CombatDen defaults in MobileApp's `design_constants.dart`.
class EngineTokens {
  EngineTokens._();

  /// Default icon edge length (matches `DesignConstants.iconSizeMd`).
  static const double iconSizeMd = 24;

  /// Material Symbol stroke weight (matches `DesignConstants.iconWeight`).
  static const double iconWeight = 300.0;

  /// Last-resort icon tint when no colour and no ambient `IconTheme` apply.
  /// The live default resolves `ThemeColor.token('text', ...)` against this.
  static const Color fallbackIconColor = Color(0xFFF4F3EE);
}
