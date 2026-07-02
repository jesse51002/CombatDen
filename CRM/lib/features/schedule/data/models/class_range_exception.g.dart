// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'class_range_exception.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ClassRangeException _$ClassRangeExceptionFromJson(Map<String, dynamic> json) =>
    ClassRangeException(
      exceptionId: json['exception_id'] as String,
      classId: json['class_id'] as String,
      gymId: json['gym_id'] as String,
      startDate: DateTime.parse(json['start_date'] as String),
      endDate: DateTime.parse(json['end_date'] as String),
      isCancelled: json['is_cancelled'] as bool,
      newInstructorId: json['new_instructor_id'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
