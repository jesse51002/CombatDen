import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

import 'package:crm/features/check_in/data/models/check_in_skip_reason.dart';

part 'check_in_response.g.dart';

/// Response for the single staff check-in (`POST /api/v1/classes/checkin`).
///
/// Mirrors the backend `CheckinResponse`. A skipped check-in writes nothing:
/// [logId] is null and [skipReason] explains why. An idempotent repeat returns
/// the existing [logId] with [alreadyCheckedIn] true and no points.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createToJson: false,
)
class CheckInResponse extends Equatable {
  final String? logId;
  final String memberId;
  final String classHistoryId;
  final String classId;
  final bool alreadyCheckedIn;
  final String? chosenPlanId;
  final String? chosenItemId;
  @JsonKey(defaultValue: 0)
  final int pointsAwarded;
  @JsonKey(fromJson: skipReasonFromJson)
  final CheckInSkipReason? skipReason;

  const CheckInResponse({
    this.logId,
    required this.memberId,
    required this.classHistoryId,
    required this.classId,
    required this.alreadyCheckedIn,
    this.chosenPlanId,
    this.chosenItemId,
    this.pointsAwarded = 0,
    this.skipReason,
  });

  factory CheckInResponse.fromJson(Map<String, dynamic> json) =>
      _$CheckInResponseFromJson(json);

  /// A fresh attendance row was recorded (points awarded) — not a skip and not
  /// an idempotent repeat.
  bool get isRecorded => logId != null && !alreadyCheckedIn;

  /// The check-in was rejected by a gate (nothing written) — the "check in
  /// anyway" override path.
  bool get isSkipped => skipReason != null;

  @override
  List<Object?> get props => [
        logId,
        memberId,
        classHistoryId,
        classId,
        alreadyCheckedIn,
        chosenPlanId,
        chosenItemId,
        pointsAwarded,
        skipReason,
      ];
}
