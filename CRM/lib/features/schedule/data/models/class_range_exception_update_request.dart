import 'package:json_annotation/json_annotation.dart';

part 'class_range_exception_update_request.g.dart';

/// Body for `PUT /api/v1/classes/{class_id}/exceptions/range/{exception_id}`
/// — move a range exception's dates.
///
/// Tracks the backend `ClassRangeExceptionUpdateRequest`
/// (`../FastApiBackend/src/classes/schema/classes_crud_schema.py`).
/// [startDate] / [endDate] are inclusive local dates (`YYYY-MM-DD`).
/// `is_cancelled` / `new_instructor_id` are fixed at creation and are not
/// part of this body — only the dates move.
@JsonSerializable(fieldRename: FieldRename.snake, createFactory: false)
class ClassRangeExceptionUpdateRequest {
  /// `YYYY-MM-DD`, inclusive.
  final String startDate;

  /// `YYYY-MM-DD`, inclusive.
  final String endDate;

  const ClassRangeExceptionUpdateRequest({
    required this.startDate,
    required this.endDate,
  });

  Map<String, dynamic> toJson() =>
      _$ClassRangeExceptionUpdateRequestToJson(this);
}
