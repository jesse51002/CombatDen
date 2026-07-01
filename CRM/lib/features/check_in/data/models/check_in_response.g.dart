// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'check_in_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CheckInResponse _$CheckInResponseFromJson(Map<String, dynamic> json) =>
    CheckInResponse(
      logId: json['log_id'] as String?,
      memberId: json['member_id'] as String,
      classHistoryId: json['class_history_id'] as String,
      classId: json['class_id'] as String,
      alreadyCheckedIn: json['already_checked_in'] as bool,
      chosenPlanId: json['chosen_plan_id'] as String?,
      chosenItemId: json['chosen_item_id'] as String?,
      pointsAwarded: (json['points_awarded'] as num?)?.toInt() ?? 0,
      skipReason: checkInWarningFromJson(json['skip_reason'] as String?),
      warnings: json['warnings'] == null
          ? const []
          : checkInWarningsFromJson(json['warnings'] as List?),
      requiresConfirmation: json['requires_confirmation'] as bool? ?? false,
      classStreakWeeks: (json['class_streak_weeks'] as num?)?.toInt() ?? 0,
    );
