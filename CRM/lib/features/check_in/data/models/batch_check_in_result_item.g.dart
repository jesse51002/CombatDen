// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'batch_check_in_result_item.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

BatchCheckInResultItem _$BatchCheckInResultItemFromJson(
  Map<String, dynamic> json,
) => BatchCheckInResultItem(
  memberId: json['member_id'] as String,
  status: ClassCheckInStatus.fromJson(json['status'] as String),
  reason: json['reason'] as String?,
  pointsAwarded: (json['points_awarded'] as num?)?.toInt() ?? 0,
  chosenPlanId: json['chosen_plan_id'] as String?,
  chosenItemId: json['chosen_item_id'] as String?,
  logId: json['log_id'] as String?,
  warnings: json['warnings'] == null
      ? const []
      : checkInWarningsFromJson(json['warnings'] as List?),
);
