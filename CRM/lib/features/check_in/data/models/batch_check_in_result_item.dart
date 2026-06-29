import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

import 'package:crm/features/check_in/data/models/class_check_in_status.dart';

part 'batch_check_in_result_item.g.dart';

/// One member's result inside a batch staff check-in.
///
/// Mirrors the backend `BatchCheckinItemResult`. [reason] is the skip reason
/// (a `CheckInSkipReason` code) when [status] is skipped, or the error message
/// when failed; null on the two success outcomes. [pointsAwarded] is the
/// class's points on a fresh check-in, 0 otherwise.
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

  const BatchCheckInResultItem({
    required this.memberId,
    required this.status,
    this.reason,
    this.pointsAwarded = 0,
    this.chosenPlanId,
    this.chosenItemId,
    this.logId,
  });

  factory BatchCheckInResultItem.fromJson(Map<String, dynamic> json) =>
      _$BatchCheckInResultItemFromJson(json);

  /// True for skipped / failed — the outcomes a "check in anyway" retry
  /// resubmits.
  bool get isUnresolved => status.isSkipped || status.isFailed;

  @override
  List<Object?> get props => [
        memberId,
        status,
        reason,
        pointsAwarded,
        chosenPlanId,
        chosenItemId,
        logId,
      ];
}
