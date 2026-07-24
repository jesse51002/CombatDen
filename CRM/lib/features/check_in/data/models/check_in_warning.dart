import 'package:json_annotation/json_annotation.dart';

/// A gate condition surfaced on a staff check-in.
///
/// Mirrors the backend `CheckinWarning`
/// (`../FastApiBackend/src/checkin/schema/checkin_schema.py`). The backend uses
/// one enum for both the (kiosk-only) `skip_reason` and the staff `warnings`
/// list. A CRM check-in is always staff (`is_member: false`), so it is never
/// rejected outright — but a warning does NOT record it either: the response
/// comes back `requires_confirmation` with `log_id: null` and nothing written,
/// and "Check in anyway" (`ignore_warnings: true`) is what records it. A clean
/// check-in records on the first request. [unknown] is the resilient fallback
/// so a new backend value never crashes the UI.
///
/// [overdue] means the member is past due. It blocks a member self-admitting
/// at a kiosk, but on this staff surface it is a warning like any other: the
/// check-in is held and "Check in anyway" records it. A past-due date can be a
/// false alarm (a payment retry in flight, cash not yet recorded), which is
/// exactly why the front desk keeps the override.
@JsonEnum(valueField: 'value')
enum CheckInWarning {
  noMembership('no_membership', 'No active membership'),
  outOfClasses('out_of_classes', 'Out of classes'),
  ineligiblePlan('ineligible_plan', 'Not eligible for this class'),
  overCapacity('over_capacity', 'Class is full'),
  unsignedWaiver('unsigned_waiver', 'Required waiver not signed'),
  overdue('overdue', 'Payment overdue'),
  unknown('unknown', 'Heads up');

  const CheckInWarning(this.value, this.displayLabel);

  final String value;
  final String displayLabel;

  static CheckInWarning fromValue(String value) {
    return CheckInWarning.values.firstWhere(
      (v) => v.value == value,
      orElse: () => CheckInWarning.unknown,
    );
  }

  String toJson() => value;

  /// Humanize a raw `reason` string from a batch result item, where `reason` is
  /// a free string: a known warning code maps to its friendly label; anything
  /// else (e.g. a `failed` item's error message) is returned as-is.
  static String humanize(String? reason) {
    if (reason == null || reason.isEmpty) return 'Heads up';
    final match = CheckInWarning.values.where((v) => v.value == reason);
    return match.isEmpty ? reason : match.first.displayLabel;
  }

  /// Join a warnings list into one short note (e.g.
  /// `No active membership · Class is full`). Empty when there are none.
  static String summarize(List<CheckInWarning> warnings) =>
      warnings.map((w) => w.displayLabel).join(' · ');
}

/// `json_serializable` adapter for the nullable `skip_reason` field — passes a
/// null straight through and resolves any string to a [CheckInWarning].
CheckInWarning? checkInWarningFromJson(String? value) =>
    value == null ? null : CheckInWarning.fromValue(value);

/// `json_serializable` adapter for a `warnings` list — resilient per-element
/// parse (a null/absent list becomes empty).
List<CheckInWarning> checkInWarningsFromJson(List<dynamic>? value) =>
    value == null
        ? const []
        : value.map((e) => CheckInWarning.fromValue(e as String)).toList();
