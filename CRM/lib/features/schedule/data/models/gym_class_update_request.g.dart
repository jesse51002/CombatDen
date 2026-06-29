// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'gym_class_update_request.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Map<String, dynamic> _$GymClassUpdateDataToJson(GymClassUpdateData instance) =>
    <String, dynamic>{
      'class_name': ?instance.className,
      'class_description': ?instance.classDescription,
      'class_time': ?instance.classTime,
      'duration_minutes': ?instance.durationMinutes,
      'recurring_unit': ?_$RecurringUnitEnumMap[instance.recurringUnit],
      'recurring_interval': ?instance.recurringInterval,
      'sun': ?instance.sun,
      'mon': ?instance.mon,
      'tue': ?instance.tue,
      'wed': ?instance.wed,
      'thu': ?instance.thu,
      'fri': ?instance.fri,
      'sat': ?instance.sat,
      'sun_instructor_id': ?instance.sunInstructorId,
      'mon_instructor_id': ?instance.monInstructorId,
      'tue_instructor_id': ?instance.tueInstructorId,
      'wed_instructor_id': ?instance.wedInstructorId,
      'thu_instructor_id': ?instance.thuInstructorId,
      'fri_instructor_id': ?instance.friInstructorId,
      'sat_instructor_id': ?instance.satInstructorId,
      'start_date': ?instance.startDate,
      'end_date': ?instance.endDate,
      'max_capacity': ?instance.maxCapacity,
      'allowed_plan_ids': ?instance.allowedPlanIds,
      'image_url': ?instance.imageUrl,
      'points_worth': ?instance.pointsWorth,
    };

const _$RecurringUnitEnumMap = {
  RecurringUnit.daily: 'daily',
  RecurringUnit.weekly: 'weekly',
  RecurringUnit.monthly: 'monthly',
  RecurringUnit.unknown: 'unknown',
};

Map<String, dynamic> _$GymClassUpdateRequestToJson(
  GymClassUpdateRequest instance,
) => <String, dynamic>{'data': instance.data.toJson()};
