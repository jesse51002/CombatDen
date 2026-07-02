import 'package:json_annotation/json_annotation.dart';

import 'package:crm/features/schedule/data/models/class_slot.dart';
import 'package:crm/features/schedule/data/models/recurring_unit.dart';

part 'gym_class_create_request.g.dart';

/// Body for `POST /api/v1/classes` — create a gym class.
///
/// Tracks the backend `GymClassCreateRequest`
/// (`../FastApiBackend/src/classes/schema/classes_crud_schema.py`)
/// field-for-field. [startDate] / [endDate] are already-formatted
/// `YYYY-MM-DD` strings so JSON serialization stays trivial and matches the
/// wire shape. [weekdaySlots] is day -> ordered slot list (request-side
/// [ClassSlot]s never carry `instructor_name`): weekly -> `sun`..`sat` keys
/// (a day occurs iff its key holds a non-empty list); daily/monthly ->
/// exactly the reserved `"all"` key. `includeIfNull: false` omits the
/// untouched optional fields so the backend applies its own defaults.
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

  final int durationMinutes;
  final RecurringUnit recurringUnit;
  final int recurringInterval;
  final Map<String, List<ClassSlot>> weekdaySlots;

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
  });

  Map<String, dynamic> toJson() => _$GymClassCreateRequestToJson(this);
}
