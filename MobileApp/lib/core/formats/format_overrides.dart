import 'package:mobile_app/core/app_slots.dart';

/// Build-time overrides for the layout and motion format slots.
///
/// These make a format **deterministically selectable without a themed
/// tenant**, which is what makes the enums reviewable at all: run the
/// app with one flag and you are looking at exactly that arrangement,
/// every time, with no customization fetch involved.
///
///     flutter run --dart-define=SHELL_FORMAT=compactRail
///     flutter run --dart-define=SHELL_FORMAT=markOnly \
///                 --dart-define=MOTION_PERSONALITY=calm
///
/// Resolution order, highest first:
///   1. a widget's `formatOverride` argument  (tests, preview sheets)
///   2. these `--dart-define` values          (local review, capture)
///   3. the tenant's customization slot       (production)
///   4. the value that ships today            (fallback)
///
/// Same category as the existing `--dart-define=VIDEO_BASE_URL`: a
/// build-time developer switch, not a member-facing feature. An
/// unrecognised value is ignored by the enum parsers, so a typo
/// degrades to the shipped arrangement rather than to a broken screen.
class FormatOverrides {
  // Private constructor to prevent instantiation
  FormatOverrides._();

  /// Slot id -> overridden value. `String.fromEnvironment` is a const
  /// constructor, so this whole map folds at compile time and costs
  /// nothing when no flag is passed (every entry is the empty string).
  static const Map<String, String> _values = {
    // Layout
    CombatDenSlots.appShellFormat:
        String.fromEnvironment('SHELL_FORMAT'),
    CombatDenSlots.homeFormat: String.fromEnvironment('HOME_FORMAT'),
    CombatDenSlots.videosFormat: String.fromEnvironment('VIDEOS_FORMAT'),
    CombatDenSlots.rankFormat: String.fromEnvironment('RANK_FORMAT'),
    CombatDenSlots.rewardsFormat: String.fromEnvironment('REWARDS_FORMAT'),
    CombatDenSlots.classFormat: String.fromEnvironment('CLASS_FORMAT'),
    CombatDenSlots.celebrationFormat:
        String.fromEnvironment('CELEBRATION_FORMAT'),

    // Motion
    CombatDenSlots.motionPersonality:
        String.fromEnvironment('MOTION_PERSONALITY'),
    CombatDenSlots.celebrationIntro:
        String.fromEnvironment('CELEBRATION_INTRO'),
    CombatDenSlots.revealStyle: String.fromEnvironment('REVEAL_STYLE'),
    CombatDenSlots.loaderStyle: String.fromEnvironment('LOADER_STYLE'),
    CombatDenSlots.transitionStyle:
        String.fromEnvironment('TRANSITION_STYLE'),
    CombatDenSlots.countUpStyle: String.fromEnvironment('COUNT_UP_STYLE'),
  };

  /// The override for [slot], or null when none was passed.
  static String? read(String slot) {
    final value = _values[slot];
    if (value == null || value.isEmpty) return null;
    return value;
  }

  /// Every slot currently overridden, for the startup log line. Empty in
  /// a normal build.
  static Map<String, String> get active => {
    for (final entry in _values.entries)
      if (entry.value.isNotEmpty) entry.key: entry.value,
  };
}
