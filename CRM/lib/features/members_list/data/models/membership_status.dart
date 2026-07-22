import 'package:json_annotation/json_annotation.dart';

/// Computed membership status for CRM display.
///
/// Extends DB statuses with derived values like trial,
/// overdue, dormant, and no_membership. [unknown] is the
/// forward-compatible fallback for values the app does
/// not yet recognise.
@JsonEnum(valueField: 'value')
enum MembershipStatus {
  active('active', 'Active'),
  trial('trial', 'Trial'),
  frozen('frozen', 'Frozen'),
  cancelled('cancelled', 'Cancelled'),
  ended('ended', 'Ended'),
  overdue('overdue', 'Overdue'),

  /// Holds only short (trial / one-time) packs and has gone quiet for
  /// longer than the gym's dormancy window.
  ///
  /// Without this they read as [active] or [trial] — "in progress" for
  /// someone who bought a pack and never came back. Distinct from
  /// [cancelled] / [ended], which mean the membership itself is over.
  dormant('dormant', 'Dormant'),
  noMembership('no_membership', 'No Membership'),
  unknown('unknown', 'Unknown');

  const MembershipStatus(this.value, this.displayLabel);

  /// The snake_case value used in JSON serialization.
  final String value;

  /// Human-readable label for the UI.
  final String displayLabel;

  /// Parses a JSON string into a [MembershipStatus].
  ///
  /// Falls back to [unknown] for unrecognised values so
  /// the app stays resilient when the backend adds new
  /// statuses.
  static MembershipStatus fromJson(String value) {
    return MembershipStatus.values.firstWhere(
      (v) => v.value == value,
      orElse: () => MembershipStatus.unknown,
    );
  }

  /// Converts to a JSON string.
  String toJson() => value;
}
