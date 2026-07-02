// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'gym_class_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

GymClassResponse _$GymClassResponseFromJson(Map<String, dynamic> json) =>
    GymClassResponse(
      classId: json['class_id'] as String,
      gymId: json['gym_id'] as String,
      className: json['class_name'] as String,
      classDescription: json['class_description'] as String?,
      durationMinutes: (json['duration_minutes'] as num).toInt(),
      recurringUnit: RecurringUnit.fromJson(json['recurring_unit'] as String),
      recurringInterval: (json['recurring_interval'] as num).toInt(),
      weekdaySlots: (json['weekday_slots'] as Map<String, dynamic>).map(
        (k, e) => MapEntry(
          k,
          (e as List<dynamic>)
              .map((e) => ClassSlot.fromJson(e as Map<String, dynamic>))
              .toList(),
        ),
      ),
      startDate: DateTime.parse(json['start_date'] as String),
      endDate: json['end_date'] == null
          ? null
          : DateTime.parse(json['end_date'] as String),
      maxCapacity: (json['max_capacity'] as num?)?.toInt(),
      allowedPlanIds: (json['allowed_plan_ids'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      imageUrl: json['image_url'] as String?,
      pointsWorth: (json['points_worth'] as num).toInt(),
      isActive: json['is_active'] as bool,
      isDeleted: json['is_deleted'] as bool,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
