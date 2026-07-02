import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

import 'package:crm/features/check_in/data/models/check_in_warning.dart';
import 'package:crm/features/check_in/data/models/class_check_in_status.dart';

part 'batch_check_in_result_item.g.dart';

/// One member's result inside a batch check-in.
///
/// Mirrors the backend `BatchCheckinItemResult`. [reason] is the error message
/// when [status] is failed (or, for a kiosk batch, the skip reason); null on
/// the two success outcomes and on `needs_confirmation` (its reasons are in
/// [warnings] instead). [warnings] are the gate conditions a `needs_confirmation`
/// member was NOT recorded for (resend with `ignore_warnings: true` — "Check in
/// anyway" — to record them), or the conditions a recorded member was
/// overridden through. [pointsAwarded] is the class's points on a fresh
/// check-in, 0 otherwise.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createToJson: false,
)
class BatchCheckInResultItem extends Equatable {
  final String memberId;
  @JsonKey(fromJson: ClassCheckInStatus.fromJson)
  final ClassCheckInStatus status;
  final String? reason;
  @JsonKey(defaultValue: 0)
  final int pointsAwarded;
  final String? chosenPlanId;
  final String? chosenItemId;
  final String? logId;
  @JsonKey(fromJson: checkInWarningsFromJson)
  final List<CheckInWarning> warnings;

  const BatchCheckInResultItem({
    required this.memberId,
    required this.status,
    this.reason,
    this.pointsAwarded = 0,
    this.chosenPlanId,
    this.chosenItemId,
    this.logId,
    this.warnings = const [],
  });

  factory BatchCheckInResultItem.fromJson(Map<String, dynamic> json) =>
      _$BatchCheckInResultItemFromJson(json);

  @override
  List<Object?> get props => [
        memberId,
        status,
        reason,
        pointsAwarded,
        chosenPlanId,
        chosenItemId,
        logId,
        warnings,
      ];
}
