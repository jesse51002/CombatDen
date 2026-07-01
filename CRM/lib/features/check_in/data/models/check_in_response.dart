import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

import 'package:crm/features/check_in/data/models/check_in_warning.dart';

part 'check_in_response.g.dart';

/// Response for the single check-in (`POST /api/v1/checkin`).
///
/// Mirrors the backend `CheckinResponse`. A CRM (staff) check-in that is clean
/// (or resent with `ignore_warnings: true`) is recorded: [logId] is set and any
/// gate conditions come back in [warnings] (the attendance may carry a null
/// [chosenPlanId] / [chosenItemId] when the member has no membership). One that
/// hits a gate warning without the override is NOT recorded —
/// [requiresConfirmation] is true, [logId] is null, and [warnings] say why;
/// resend the identical request with `ignore_warnings: true` to record it. An
/// idempotent repeat returns the existing [logId] with [alreadyCheckedIn] true
/// and no points. [classStreakWeeks] is the member's weekly attendance streak
/// after this check-in (0 when not recorded). [skipReason] is the kiosk-only
/// rejection reason — always null for the CRM (`is_member: false`); parsed for
/// contract completeness.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createToJson: false,
)
class CheckInResponse extends Equatable {
  final String? logId;
  final String memberId;
  final String classId;
  final bool alreadyCheckedIn;
  final String? chosenPlanId;
  final String? chosenItemId;
  @JsonKey(defaultValue: 0)
  final int pointsAwarded;
  @JsonKey(fromJson: checkInWarningFromJson)
  final CheckInWarning? skipReason;
  @JsonKey(fromJson: checkInWarningsFromJson)
  final List<CheckInWarning> warnings;
  @JsonKey(defaultValue: false)
  final bool requiresConfirmation;
  @JsonKey(defaultValue: 0)
  final int classStreakWeeks;

  const CheckInResponse({
    this.logId,
    required this.memberId,
    required this.classId,
    required this.alreadyCheckedIn,
    this.chosenPlanId,
    this.chosenItemId,
    this.pointsAwarded = 0,
    this.skipReason,
    this.warnings = const [],
    this.requiresConfirmation = false,
    this.classStreakWeeks = 0,
  });

  factory CheckInResponse.fromJson(Map<String, dynamic> json) =>
      _$CheckInResponseFromJson(json);

  /// A fresh attendance row was recorded (points awarded) — not an idempotent
  /// repeat, and not a warning held for confirmation.
  bool get isRecorded => logId != null && !alreadyCheckedIn;

  /// Whether the recorded check-in carries any non-blocking gate warnings.
  bool get hasWarnings => warnings.isNotEmpty;

  @override
  List<Object?> get props => [
        logId,
        memberId,
        classId,
        alreadyCheckedIn,
        chosenPlanId,
        chosenItemId,
        pointsAwarded,
        skipReason,
        warnings,
        requiresConfirmation,
        classStreakWeeks,
      ];
}
