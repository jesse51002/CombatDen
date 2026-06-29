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
      classTime: json['class_time'] as String,
      durationMinutes: (json['duration_minutes'] as num).toInt(),
      recurringUnit: RecurringUnit.fromJson(json['recurring_unit'] as String),
      recurringInterval: (json['recurring_interval'] as num).toInt(),
      sun: json['sun'] as bool,
      mon: json['mon'] as bool,
      tue: json['tue'] as bool,
      wed: json['wed'] as bool,
      thu: json['thu'] as bool,
      fri: json['fri'] as bool,
      sat: json['sat'] as bool,
      sunInstructorId: json['sun_instructor_id'] as String?,
      monInstructorId: json['mon_instructor_id'] as String?,
      tueInstructorId: json['tue_instructor_id'] as String?,
      wedInstructorId: json['wed_instructor_id'] as String?,
      thuInstructorId: json['thu_instructor_id'] as String?,
      friInstructorId: json['fri_instructor_id'] as String?,
      satInstructorId: json['sat_instructor_id'] as String?,
      sunInstructorName: json['sun_instructor_name'] as String?,
      monInstructorName: json['mon_instructor_name'] as String?,
      tueInstructorName: json['tue_instructor_name'] as String?,
      wedInstructorName: json['wed_instructor_name'] as String?,
      thuInstructorName: json['thu_instructor_name'] as String?,
      friInstructorName: json['fri_instructor_name'] as String?,
      satInstructorName: json['sat_instructor_name'] as String?,
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
