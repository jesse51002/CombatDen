import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'class_range_exception.g.dart';

/// One `class_range_exceptions` row, from
/// `GET /api/v1/classes/{class_id}/exceptions/range` and the PUT/DELETE
/// mutation responses.
///
/// Tracks the backend `ClassRangeExceptionResponse`
/// (`../FastApiBackend/src/classes/schema/classes_crud_schema.py`).
/// [startDate] / [endDate] are inclusive local dates. The CRM's "Cancelled
/// ranges" surfaces only ever show/edit rows where [isCancelled] is true —
/// an instructor-substitution range never cancels an occurrence, so it has
/// no cancel-related UI here.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createToJson: false,
)
class ClassRangeException extends Equatable {
  final String exceptionId;
  final String classId;
  final String gymId;
  final DateTime startDate;
  final DateTime endDate;
  final bool isCancelled;
  final String? newInstructorId;
  final DateTime createdAt;

  const ClassRangeException({
    required this.exceptionId,
    required this.classId,
    required this.gymId,
    required this.startDate,
    required this.endDate,
    required this.isCancelled,
    this.newInstructorId,
    required this.createdAt,
  });

  factory ClassRangeException.fromJson(Map<String, dynamic> json) =>
      _$ClassRangeExceptionFromJson(json);

  @override
  List<Object?> get props => [
        exceptionId,
        classId,
        gymId,
        startDate,
        endDate,
        isCancelled,
        newInstructorId,
        createdAt,
      ];
}
