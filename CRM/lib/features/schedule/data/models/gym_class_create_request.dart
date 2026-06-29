import 'package:json_annotation/json_annotation.dart';

import 'package:crm/features/schedule/data/models/recurring_unit.dart';

part 'gym_class_create_request.g.dart';

/// Body for `POST /api/v1/classes` — create a gym class.
///
/// Tracks the backend `GymClassCreateRequest`
/// (`../FastApiBackend/src/classes/schema/classes_crud_schema.py`)
/// field-for-field. Dates and the time-of-day are carried as already-formatted
/// strings so JSON serialization stays trivial and matches the wire shape:
/// [classTime] is `HH:MM:SS`, [startDate] / [endDate] are `YYYY-MM-DD`. The
/// per-weekday `sun..sat` flags and `*InstructorId` slots mirror the columns.
/// `includeIfNull: false` omits the untouched optional fields so the backend
/// applies its own defaults.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createFactory: false,
  includeIfNull: false,
  explicitToJson: true,
)
class GymClassCreateRequest {
  final String gymId;
  final String className;
  final String? classDescription;

  /// Local start time of day as `HH:MM:SS`.
  final String classTime;
  final int durationMinutes;
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

  /// `YYYY-MM-DD`.
  final String startDate;

  /// `YYYY-MM-DD`, optional.
  final String? endDate;
  final int? maxCapacity;
  final List<String>? allowedPlanIds;
  final String? imageUrl;
  final int pointsWorth;

  const GymClassCreateRequest({
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
    required this.startDate,
    this.endDate,
    this.maxCapacity,
    this.allowedPlanIds,
    this.imageUrl,
    required this.pointsWorth,
  });

  Map<String, dynamic> toJson() => _$GymClassCreateRequestToJson(this);
}
