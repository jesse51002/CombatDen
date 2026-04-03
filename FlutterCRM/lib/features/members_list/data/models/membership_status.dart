import 'package:json_annotation/json_annotation.dart';

/// Possible membership statuses.
@JsonEnum(valueField: 'value')
enum MembershipStatus {
  active('active', 'Active'),
  trial('trial', 'Trial'),
  frozen('frozen', 'Frozen'),
  cancelled('cancelled', 'Cancelled'),
  ended('ended', 'Ended'),
  overdue('overdue', 'Overdue'),
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
