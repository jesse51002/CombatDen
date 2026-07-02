import 'package:json_annotation/json_annotation.dart';

part 'class_instance_exception_request.g.dart';

/// Body for `POST /api/v1/classes/{class_id}/exceptions/instance` — upsert the
/// single-SLOT override for one occurrence (unique per class + original_date +
/// original_time — several slots per day are legal, so the pair names exactly
/// one occurrence).
///
/// Tracks the backend `ClassInstanceExceptionUpsertRequest`
/// (`../FastApiBackend/src/classes/schema/classes_crud_schema.py`)
/// field-for-field. [originalDate] is the occurrence's local date
/// (`YYYY-MM-DD`); [originalTime] is its slot time (`HH:MM:SS`) — together
/// the occurrence's identity key. The cancel flow sets `isCancelled: true` and
/// leaves every override field null; `includeIfNull: false` omits the
/// untouched optionals, so a pure single-day cancel sends just
/// `original_date` + `original_time` + `is_cancelled`.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createFactory: false,
  includeIfNull: false,
)
class ClassInstanceExceptionRequest {
  /// The occurrence's original local date (`YYYY-MM-DD`).
  final String originalDate;

  /// The occurrence's original slot time (`HH:MM:SS`) — the other half of
  /// the occurrence's identity key.
  final String originalTime;
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
    required this.originalTime,
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
