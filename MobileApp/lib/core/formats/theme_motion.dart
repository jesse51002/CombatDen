import 'package:mobile_app/core/app_slots.dart';
import 'package:mobile_app/core/formats/format_overrides.dart';
import 'package:mobile_app/core/formats/format_store.dart';
import 'package:mobile_app/core/formats/motion_formats.dart';
import 'package:mobile_app/core/formats/motion_spec.dart';
import 'package:theme_flutter/theme/theme_text.dart';

/// Resolves the active motion formats from the loaded customization.
///
/// Same seam and same safety guarantees as `ThemeLayout` — see its doc
/// comment for why this reads the engine's existing string-slot reader
/// instead of adding a slot kind to the shared package.
class ThemeMotion {
  // Private constructor to prevent instantiation
  ThemeMotion._();

  static String? _read(String slot) {
    // The in-app dev picker wins over everything, then a --dart-define,
    // then the tenant's slot. See `FormatStore` for the full order.
    final pinned = FormatStore.instance.read(slot);
    if (pinned != null) return pinned;
    final override = FormatOverrides.read(slot);
    if (override != null) return override;
    final value = ThemeText.value(slot, fallback: '');
    return value.isEmpty ? null : value;
  }

  static MotionPersonality personality() =>
      MotionPersonality.fromWire(_read(CombatDenSlots.motionPersonality));

  /// The resolved timing set for the active personality. Read this at
  /// build time rather than caching it: a live style switch re-keys the
  /// app and every widget re-resolves.
  static MotionSpec spec() => MotionSpec.forPersonality(personality());

  static CelebrationIntro celebrationIntro() =>
      CelebrationIntro.fromWire(_read(CombatDenSlots.celebrationIntro));

  static RevealStyle reveal() =>
      RevealStyle.fromWire(_read(CombatDenSlots.revealStyle));

  static LoaderStyle loader() =>
      LoaderStyle.fromWire(_read(CombatDenSlots.loaderStyle));

  static TransitionStyle transition() =>
      TransitionStyle.fromWire(_read(CombatDenSlots.transitionStyle));

  static CountUpStyle countUp() =>
      CountUpStyle.fromWire(_read(CombatDenSlots.countUpStyle));
}
