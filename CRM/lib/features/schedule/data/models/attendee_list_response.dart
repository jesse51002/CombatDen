import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'attendee_list_response.g.dart';

/// One member who attended a class occurrence.
///
/// Mirrors the backend `Attendee`
/// (`../FastApiBackend/src/checkin/schema/checkin_schema.py`). [planId] /
/// [itemId] are null for a no-membership staff check-in.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createToJson: false,
)
class Attendee extends Equatable {
  final String memberId;
  final String fullName;
  final String logId;
  final String? planId;
  final String? itemId;

  const Attendee({
    required this.memberId,
    required this.fullName,
    required this.logId,
    this.planId,
    this.itemId,
  });

  factory Attendee.fromJson(Map<String, dynamic> json) =>
      _$AttendeeFromJson(json);

  @override
  List<Object?> get props => [memberId, fullName, logId, planId, itemId];
}

/// Response for `GET /api/v1/checkin/attendees`.
///
/// Mirrors the backend `AttendeeListResponse`. [classHistoryId] is null when
/// the occurrence was never materialized (no check-ins yet) — [attendees] is
/// then empty.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createToJson: false,
)
class AttendeeListResponse extends Equatable {
  final String classId;

  /// The gym-local calendar date queried, echoed back as a bare `YYYY-MM-DD`.
  final String occurrenceDate;
  final String? classHistoryId;
  @JsonKey(defaultValue: [])
  final List<Attendee> attendees;

  const AttendeeListResponse({
    required this.classId,
    required this.occurrenceDate,
    this.classHistoryId,
    this.attendees = const [],
  });

  factory AttendeeListResponse.fromJson(Map<String, dynamic> json) =>
      _$AttendeeListResponseFromJson(json);

  @override
  List<Object?> get props =>
      [classId, occurrenceDate, classHistoryId, attendees];
}
