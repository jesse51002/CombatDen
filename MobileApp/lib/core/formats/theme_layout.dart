import 'package:mobile_app/core/app_slots.dart';
import 'package:mobile_app/core/formats/format_overrides.dart';
import 'package:mobile_app/core/formats/layout_formats.dart';
import 'package:theme_flutter/theme/theme_text.dart';

/// Resolves the active layout format for each screen from the loaded
/// customization.
///
/// Deliberately built on the engine's existing string-slot reader
/// (`ThemeText.value`) rather than on a new slot kind inside the shared
/// `theme_flutter` package. A platform adopting the engine should not
/// have to change its architecture to get layout selection, and this
/// app is the reference implementation of that constraint. `ThemeText`
/// already returns the fallback when no customization is loaded, the
/// slot is absent, or DI is not registered (widget tests), and never
/// throws — so every accessor here is safe in every context.
///
/// If the engine later promotes layout to a first-class `layout_set`,
/// only the two lines inside [_read] change; every call site and every
/// screen stays as it is.
class ThemeLayout {
  // Private constructor to prevent instantiation
  ThemeLayout._();

  static String? _read(String slot) {
    // A --dart-define wins over the tenant's slot so a format can be
    // reviewed deterministically without a themed tenant.
    final override = FormatOverrides.read(slot);
    if (override != null) return override;
    final value = ThemeText.value(slot, fallback: '');
    return value.isEmpty ? null : value;
  }

  static AppShellFormat shell() =>
      AppShellFormat.fromWire(_read(CombatDenSlots.appShellFormat));

  static HomeFormat home() =>
      HomeFormat.fromWire(_read(CombatDenSlots.homeFormat));

  static VideosFormat videos() =>
      VideosFormat.fromWire(_read(CombatDenSlots.videosFormat));

  static RankFormat rank() =>
      RankFormat.fromWire(_read(CombatDenSlots.rankFormat));

  static RewardsFormat rewards() =>
      RewardsFormat.fromWire(_read(CombatDenSlots.rewardsFormat));

  static ClassFormat classDetail() =>
      ClassFormat.fromWire(_read(CombatDenSlots.classFormat));

  static CelebrationFormat celebration() =>
      CelebrationFormat.fromWire(_read(CombatDenSlots.celebrationFormat));
}
