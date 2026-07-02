import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

import 'package:crm/features/schedule/data/models/class_slot.dart';
import 'package:crm/features/schedule/data/models/recurring_unit.dart';

part 'gym_class_response.g.dart';

/// A single `gym_classes` row, from `GET /api/v1/classes?gym_id=…`.
///
/// Tracks the backend `GymClassResponse` field-for-field. [weekdaySlots] is
/// day -> ordered slot list: weekly schedules use `sun`..`sat` keys (a day
/// occurs iff its key holds a non-empty list, several times per day allowed);
/// daily/monthly schedules use exactly the reserved `"all"` key. Each slot's
/// `instructor_name` is the resolved `first_name last_name` joined from
/// `gym_employees` (null when that slot has no instructor).
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createToJson: false,
)
class GymClassResponse extends Equatable {
  final String classId;
  final String gymId;
  final String className;
  final String? classDescription;

  final int durationMinutes;
  @JsonKey(fromJson: RecurringUnit.fromJson)
  final RecurringUnit recurringUnit;
  final int recurringInterval;
  final Map<String, List<ClassSlot>> weekdaySlots;
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
    required this.durationMinutes,
    required this.recurringUnit,
    required this.recurringInterval,
    required this.weekdaySlots,
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
        durationMinutes,
        recurringUnit,
        recurringInterval,
        weekdaySlots,
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
