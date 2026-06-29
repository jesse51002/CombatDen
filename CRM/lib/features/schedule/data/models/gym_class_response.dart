import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

import 'package:crm/features/schedule/data/models/recurring_unit.dart';

part 'gym_class_response.g.dart';

/// A single `gym_classes` row, from `GET /api/v1/classes?gym_id=…`.
///
/// Tracks the backend `GymClassResponse` field-for-field. The seven
/// `*InstructorName` fields are the resolved `first_name last_name` joined
/// from `gym_employees` for each weekday's instructor slot (null when that
/// slot has no instructor). [classTime] is a bare local time string
/// (`HH:MM:SS`) — render as given, no timezone math.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createToJson: false,
)
class GymClassResponse extends Equatable {
  final String classId;
  final String gymId;
  final String className;
  final String? classDescription;

  /// Local start time of day as `HH:MM:SS` (gym-local; render as given).
  final String classTime;
  final int durationMinutes;
  @JsonKey(fromJson: RecurringUnit.fromJson)
  final RecurringUnit recurringUnit;
  final int recurringInterval;
  final bool sun;
  final bool mon;
  final bool tue;
  final bool wed;
  final bool thu;
  final bool fri;
  final bool sat;
  final String? sunInstructorId;
  final String? monInstructorId;
  final String? tueInstructorId;
  final String? wedInstructorId;
  final String? thuInstructorId;
  final String? friInstructorId;
  final String? satInstructorId;
  final String? sunInstructorName;
  final String? monInstructorName;
  final String? tueInstructorName;
  final String? wedInstructorName;
  final String? thuInstructorName;
  final String? friInstructorName;
  final String? satInstructorName;
  final DateTime startDate;
  final DateTime? endDate;
  final int? maxCapacity;
  final List<String>? allowedPlanIds;
  final String? imageUrl;
  final int pointsWorth;
  final bool isActive;
  final bool isDeleted;
  final DateTime createdAt;

  const GymClassResponse({
    required this.classId,
    required this.gymId,
    required this.className,
    this.classDescription,
    required this.classTime,
    required this.durationMinutes,
    required this.recurringUnit,
    required this.recurringInterval,
    required this.sun,
    required this.mon,
    required this.tue,
    required this.wed,
    required this.thu,
    required this.fri,
    required this.sat,
    this.sunInstructorId,
    this.monInstructorId,
    this.tueInstructorId,
    this.wedInstructorId,
    this.thuInstructorId,
    this.friInstructorId,
    this.satInstructorId,
    this.sunInstructorName,
    this.monInstructorName,
    this.tueInstructorName,
    this.wedInstructorName,
    this.thuInstructorName,
    this.friInstructorName,
    this.satInstructorName,
    required this.startDate,
    this.endDate,
    this.maxCapacity,
    this.allowedPlanIds,
    this.imageUrl,
    required this.pointsWorth,
    required this.isActive,
    required this.isDeleted,
    required this.createdAt,
  });

  factory GymClassResponse.fromJson(Map<String, dynamic> json) =>
      _$GymClassResponseFromJson(json);

  @override
  List<Object?> get props => [
        classId,
        gymId,
        className,
        classDescription,
        classTime,
        durationMinutes,
        recurringUnit,
        recurringInterval,
        sun,
        mon,
        tue,
        wed,
        thu,
        fri,
        sat,
        sunInstructorId,
        monInstructorId,
        tueInstructorId,
        wedInstructorId,
        thuInstructorId,
        friInstructorId,
        satInstructorId,
        sunInstructorName,
        monInstructorName,
        tueInstructorName,
        wedInstructorName,
        thuInstructorName,
        friInstructorName,
        satInstructorName,
        startDate,
        endDate,
        maxCapacity,
        allowedPlanIds,
        imageUrl,
        pointsWorth,
        isActive,
        isDeleted,
        createdAt,
      ];
}
