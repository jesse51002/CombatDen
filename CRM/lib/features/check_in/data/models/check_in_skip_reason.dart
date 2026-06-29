import 'package:json_annotation/json_annotation.dart';

/// Why a non-override check-in was skipped (no attendance written).
///
/// Mirrors the backend `CheckinSkipReason`
/// (`../FastApiBackend/src/classes/schema/classes_schema.py`). [unknown] is the
/// resilient fallback so a new backend reason never crashes the UI.
@JsonEnum(valueField: 'value')
enum CheckInSkipReason {
  capacityFull('capacity_full', 'Class is full'),
  noMembership('no_membership', 'No active membership'),
  noEligiblePlan(
    'no_eligible_plan',
    'No membership covers this class',
  ),
  unknown('unknown', 'Not eligible');

  const CheckInSkipReason(this.value, this.displayLabel);

  final String value;
  final String displayLabel;

  static CheckInSkipReason fromValue(String value) {
    return CheckInSkipReason.values.firstWhere(
      (v) => v.value == value,
      orElse: () => CheckInSkipReason.unknown,
    );
  }

  String toJson() => value;

  /// Humanize a raw reason string from a batch result item, where `reason` is a
  /// free string: a known skip-reason code maps to its friendly label; anything
  /// else (e.g. a failure message) is returned as-is.
  static String humanize(String? reason) {
    if (reason == null || reason.isEmpty) return 'Not eligible';
    final match =
        CheckInSkipReason.values.where((v) => v.value == reason);
    return match.isEmpty ? reason : match.first.displayLabel;
  }
}

/// `json_serializable` adapter for the nullable `skip_reason` field — passes a
/// null straight through and resolves any string to a [CheckInSkipReason].
CheckInSkipReason? skipReasonFromJson(String? value) =>
    value == null ? null : CheckInSkipReason.fromValue(value);
