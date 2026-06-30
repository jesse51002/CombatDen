import 'package:json_annotation/json_annotation.dart';

/// Per-member outcome inside a batch staff check-in.
///
/// Mirrors the backend `BatchCheckinItemStatus`
/// (`../FastApiBackend/src/checkin/schema/batch_checkin_schema.py`).
/// [unknown] is the resilient fallback so a new backend status never crashes
/// the results UI.
@JsonEnum(valueField: 'value')
enum ClassCheckInStatus {
  checkedIn('checked_in', 'Checked in'),
  alreadyCheckedIn('already_checked_in', 'Already checked in'),
  skipped('skipped', 'Skipped'),
  failed('failed', 'Failed'),
  unknown('unknown', 'Unknown');

  const ClassCheckInStatus(this.value, this.displayLabel);

  final String value;
  final String displayLabel;

  static ClassCheckInStatus fromJson(String value) {
    return ClassCheckInStatus.values.firstWhere(
      (v) => v.value == value,
      orElse: () => ClassCheckInStatus.unknown,
    );
  }

  String toJson() => value;

  bool get isCheckedIn => this == ClassCheckInStatus.checkedIn;
  bool get isAlreadyCheckedIn =>
      this == ClassCheckInStatus.alreadyCheckedIn;
  bool get isSkipped => this == ClassCheckInStatus.skipped;
  bool get isFailed => this == ClassCheckInStatus.failed;

  /// A recorded or pre-existing attendance row (the two "green" outcomes).
  bool get isSuccess => isCheckedIn || isAlreadyCheckedIn;
}
