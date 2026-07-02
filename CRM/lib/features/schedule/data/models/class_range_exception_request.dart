import 'package:json_annotation/json_annotation.dart';

part 'class_range_exception_request.g.dart';

/// Body for `POST /api/v1/classes/{class_id}/exceptions/range` — cancel (or
/// substitute an instructor across) a continuous date range.
///
/// Tracks the backend `ClassRangeExceptionCreateRequest`
/// (`../FastApiBackend/src/classes/schema/classes_crud_schema.py`).
/// [startDate] / [endDate] are inclusive local dates (`YYYY-MM-DD`). The cancel
/// flow sets `isCancelled: true` and omits [newInstructorId]
/// (`includeIfNull: false`), satisfying the backend's "cancel OR substitute"
/// CHECK.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createFactory: false,
  includeIfNull: false,
)
class ClassRangeExceptionRequest {
  /// `YYYY-MM-DD`, inclusive.
  final String startDate;

  /// `YYYY-MM-DD`, inclusive.
  final String endDate;
  final bool isCancelled;

  /// Instructor substitution — unused by the cancel flow, carried for contract
  /// fidelity.
  final String? newInstructorId;

  const ClassRangeExceptionRequest({
    required this.startDate,
    required this.endDate,
    required this.isCancelled,
    this.newInstructorId,
  });

  Map<String, dynamic> toJson() => _$ClassRangeExceptionRequestToJson(this);
}
