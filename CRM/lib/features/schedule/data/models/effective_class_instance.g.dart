// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'effective_class_instance.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

EffectiveClassInstance _$EffectiveClassInstanceFromJson(
  Map<String, dynamic> json,
) => EffectiveClassInstance(
  classId: json['class_id'] as String,
  gymId: json['gym_id'] as String,
  className: json['class_name'] as String,
  classDate: DateTime.parse(json['class_date'] as String),
  originalDate: DateTime.parse(json['original_date'] as String),
  originalTime: json['original_time'] as String,
  occurredAt: DateTime.parse(json['occurred_at'] as String),
  resolvedClassTime: json['resolved_class_time'] as String,
  resolvedDurationMinutes: (json['resolved_duration_minutes'] as num).toInt(),
  resolvedInstructorId: json['resolved_instructor_id'] as String?,
  resolvedInstructorName: json['resolved_instructor_name'] as String?,
  imageUrl: json['image_url'] as String?,
  pointsWorth: (json['points_worth'] as num).toInt(),
  isActive: json['is_active'] as bool? ?? true,
  maxCapacity: (json['max_capacity'] as num?)?.toInt(),
  isCancelled: json['is_cancelled'] as bool,
  hasInstanceException: json['has_instance_exception'] as bool,
  hasRangeException: json['has_range_exception'] as bool,
  cancellingRangeId: json['cancelling_range_id'] as String?,
  attendanceCount: (json['attendance_count'] as num?)?.toInt() ?? 0,
  signupCount: (json['signup_count'] as num?)?.toInt() ?? 0,
);
