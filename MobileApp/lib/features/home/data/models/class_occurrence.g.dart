// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'class_occurrence.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ClassOccurrence _$ClassOccurrenceFromJson(
  Map<String, dynamic> json,
) => ClassOccurrence(
  classId: json['class_id'] as String,
  gymId: json['gym_id'] as String,
  className: json['class_name'] as String,
  classDate: json['class_date'] as String,
  originalDate: json['original_date'] as String,
  originalTime: json['original_time'] as String,
  occurredAt: json['occurred_at'] as String,
  resolvedClassTime: json['resolved_class_time'] as String,
  resolvedDurationMinutes: (json['resolved_duration_minutes'] as num).toInt(),
  imageUrl: json['image_url'] as String,
  pointsWorth: (json['points_worth'] as num).toInt(),
  isCancelled: json['is_cancelled'] as bool,
  hasInstanceException: json['has_instance_exception'] as bool,
  hasRangeException: json['has_range_exception'] as bool,
  resolvedInstructorId: json['resolved_instructor_id'] as String?,
  resolvedInstructorName: json['resolved_instructor_name'] as String?,
  resolvedInstructorBio: json['resolved_instructor_bio'] as String?,
  resolvedInstructorImageUrl: json['resolved_instructor_image_url'] as String?,
  classDescription: json['class_description'] as String?,
  maxCapacity: (json['max_capacity'] as num?)?.toInt(),
  cancellingRangeId: json['cancelling_range_id'] as String?,
  attendanceCount: (json['attendance_count'] as num?)?.toInt() ?? 0,
  signupCount: (json['signup_count'] as num?)?.toInt() ?? 0,
);
