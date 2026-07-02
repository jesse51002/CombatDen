// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'gym_class_create_request.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Map<String, dynamic> _$GymClassCreateRequestToJson(
  GymClassCreateRequest instance,
) => <String, dynamic>{
  'gym_id': instance.gymId,
  'class_name': instance.className,
  'class_description': ?instance.classDescription,
  'duration_minutes': instance.durationMinutes,
  'recurring_unit': _$RecurringUnitEnumMap[instance.recurringUnit]!,
  'recurring_interval': instance.recurringInterval,
  'weekday_slots': instance.weekdaySlots.map(
    (k, e) => MapEntry(k, e.map((e) => e.toJson()).toList()),
  ),
  'start_date': instance.startDate,
  'end_date': ?instance.endDate,
  'max_capacity': ?instance.maxCapacity,
  'allowed_plan_ids': ?instance.allowedPlanIds,
  'image_url': ?instance.imageUrl,
  'points_worth': instance.pointsWorth,
};

const _$RecurringUnitEnumMap = {
  RecurringUnit.daily: 'daily',
  RecurringUnit.weekly: 'weekly',
  RecurringUnit.monthly: 'monthly',
  RecurringUnit.unknown: 'unknown',
};
