import 'package:mobile_app/core/app_slots.dart';
import 'package:mobile_app/core/formats/layout_formats.dart';
import 'package:mobile_app/core/formats/motion_formats.dart';

/// One switchable format: which slot it writes, what to call it, and the
/// values it accepts.
class FormatEntry {
  const FormatEntry({
    required this.slot,
    required this.label,
    required this.values,
    required this.implemented,
  });

  final String slot;
  final String label;

  /// Enum value names, in declaration order. The first is what ships.
  final List<String> values;

  /// Whether the screen actually honours this slot yet. The picker still
  /// lists the rest so the intended surface is visible while it is being
  /// built out, rather than appearing one screen at a time.
  final bool implemented;

  String get shipped => values.first;
}

List<String> _names(List<Enum> values) =>
    values.map((v) => v.name).toList(growable: false);

/// Every layout format, in screen order.
final List<FormatEntry> kLayoutFormats = [
  FormatEntry(
    slot: CombatDenSlots.appShellFormat,
    label: 'Shell',
    values: _names(AppShellFormat.values),
    implemented: true,
  ),
  FormatEntry(
    slot: CombatDenSlots.homeFormat,
    label: 'Home',
    values: _names(HomeFormat.values),
    implemented: true,
  ),
  FormatEntry(
    slot: CombatDenSlots.videosFormat,
    label: 'Videos',
    values: _names(VideosFormat.values),
    implemented: true,
  ),
  FormatEntry(
    slot: CombatDenSlots.rankFormat,
    label: 'Rank',
    values: _names(RankFormat.values),
    implemented: true,
  ),
  FormatEntry(
    slot: CombatDenSlots.rewardsFormat,
    label: 'Rewards',
    values: _names(RewardsFormat.values),
    implemented: true,
  ),
  FormatEntry(
    slot: CombatDenSlots.classFormat,
    label: 'Class detail',
    values: _names(ClassFormat.values),
    implemented: true,
  ),
  FormatEntry(
    slot: CombatDenSlots.celebrationFormat,
    label: 'Celebration',
    values: _names(CelebrationFormat.values),
    implemented: true,
  ),
];

/// Every motion format.
final List<FormatEntry> kMotionFormats = [
  FormatEntry(
    slot: CombatDenSlots.motionPersonality,
    label: 'Personality',
    values: _names(MotionPersonality.values),
    implemented: false,
  ),
  FormatEntry(
    slot: CombatDenSlots.celebrationIntro,
    label: 'Celebration intro',
    values: _names(CelebrationIntro.values),
    implemented: true,
  ),
  FormatEntry(
    slot: CombatDenSlots.revealStyle,
    label: 'Reveal',
    values: _names(RevealStyle.values),
    implemented: true,
  ),
  FormatEntry(
    slot: CombatDenSlots.loaderStyle,
    label: 'Loader',
    values: _names(LoaderStyle.values),
    implemented: true,
  ),
  FormatEntry(
    slot: CombatDenSlots.transitionStyle,
    label: 'Transition',
    values: _names(TransitionStyle.values),
    implemented: false,
  ),
  FormatEntry(
    slot: CombatDenSlots.countUpStyle,
    label: 'Count-up',
    values: _names(CountUpStyle.values),
    implemented: false,
  ),
];
