// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'gym_class_update_request.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Map<String, dynamic> _$GymClassIdentityUpdateDataToJson(
  GymClassIdentityUpdateData instance,
) => <String, dynamic>{
  'class_name': ?instance.className,
  'class_description': ?instance.classDescription,
  'max_capacity': ?instance.maxCapacity,
  'allowed_plan_ids': ?instance.allowedPlanIds,
  'image_url': ?instance.imageUrl,
  'points_worth': ?instance.pointsWorth,
  'is_active': ?instance.isActive,
};

Map<String, dynamic> _$GymClassScheduleFieldsToJson(
  GymClassScheduleFields instance,
) => <String, dynamic>{
  'duration_minutes': instance.durationMinutes,
  'recurring_unit': _$RecurringUnitEnumMap[instance.recurringUnit]!,
  'recurring_interval': instance.recurringInterval,
  'weekday_slots': instance.weekdaySlots.map(
    (k, e) => MapEntry(k, e.map((e) => e.toJson()).toList()),
  ),
  'start_date': instance.startDate,
  'end_date': instance.endDate,
};

const _$RecurringUnitEnumMap = {
  RecurringUnit.daily: 'daily',
  RecurringUnit.weekly: 'weekly',
  RecurringUnit.monthly: 'monthly',
  RecurringUnit.unknown: 'unknown',
};

Map<String, dynamic> _$GymClassUpdateRequestToJson(
  GymClassUpdateRequest instance,
) => <String, dynamic>{
  'identity': ?instance.identity?.toJson(),
  'schedule': ?instance.schedule?.toJson(),
};
