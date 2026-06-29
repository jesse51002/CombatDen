import 'package:json_annotation/json_annotation.dart';

part 'class_instance_exception_request.g.dart';

/// Body for `POST /api/v1/classes/{class_id}/exceptions/instance` — upsert the
/// single-date override for one occurrence (unique per class + original_date).
///
/// Tracks the backend `ClassInstanceExceptionUpsertRequest`
/// (`../FastApiBackend/src/classes/schema/classes_crud_schema.py`)
/// field-for-field. [originalDate] is the occurrence's local date
/// (`YYYY-MM-DD`). The cancel flow sets `isCancelled: true` and leaves every
/// override field null; `includeIfNull: false` omits the untouched optionals,
/// so a pure single-day cancel sends just `original_date` + `is_cancelled`.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createFactory: false,
  includeIfNull: false,
)
class ClassInstanceExceptionRequest {
  /// The occurrence's original local date (`YYYY-MM-DD`).
  final String originalDate;
  final bool isCancelled;

  /// Reschedule / override fields — unused by the cancel flow, carried so the
  /// model tracks the full backend contract. `HH:MM:SS` / `YYYY-MM-DD` strings.
  final String? newClassTime;
  final int? newDurationMinutes;
  final int? newMaxCapacity;
  final String? newInstructorId;
  final String? newDate;

  const ClassInstanceExceptionRequest({
    required this.originalDate,
    required this.isCancelled,
    this.newClassTime,
    this.newDurationMinutes,
    this.newMaxCapacity,
    this.newInstructorId,
    this.newDate,
  });

  Map<String, dynamic> toJson() =>
      _$ClassInstanceExceptionRequestToJson(this);
}
