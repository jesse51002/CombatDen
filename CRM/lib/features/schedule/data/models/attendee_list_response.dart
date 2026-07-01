import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'attendee_list_response.g.dart';

/// One member who signed up for, attended, or both, a class occurrence.
///
/// Mirrors the backend `Attendee`
/// (`../FastApiBackend/src/checkin/schema/checkin_schema.py`). [logId] /
/// [planId] / [itemId] are null when [attended] is false (a signed-up-only
/// member); [planId] / [itemId] can also be null on an attended row for a
/// no-membership staff check-in.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createToJson: false,
)
class Attendee extends Equatable {
  final String memberId;
  final String fullName;

  /// True when the member has a `class_signups` row for this occurrence.
  final bool signedUp;

  /// True when the member has a `member_attendance` row for this occurrence.
  final bool attended;
  final String? logId;
  final String? planId;
  final String? itemId;

  const Attendee({
    required this.memberId,
    required this.fullName,
    required this.signedUp,
    required this.attended,
    this.logId,
    this.planId,
    this.itemId,
  });

  factory Attendee.fromJson(Map<String, dynamic> json) =>
      _$AttendeeFromJson(json);

  @override
  List<Object?> get props =>
      [memberId, fullName, signedUp, attended, logId, planId, itemId];
}

/// Response for `GET /api/v1/checkin/attendees` — the combined roster.
///
/// Mirrors the backend `AttendeeListResponse`: everyone who signed up OR
/// attended the occurrence, each flagged. A signed-up-only member can still
/// appear in [attendees] even when nobody has attended yet.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createToJson: false,
)
class AttendeeListResponse extends Equatable {
  final String classId;

  /// The occurrence's IDENTITY date queried, echoed back as a bare
  /// `YYYY-MM-DD`.
  final String occurrenceDate;
  @JsonKey(defaultValue: [])
  final List<Attendee> attendees;

  const AttendeeListResponse({
    required this.classId,
    required this.occurrenceDate,
    this.attendees = const [],
  });

  factory AttendeeListResponse.fromJson(Map<String, dynamic> json) =>
      _$AttendeeListResponseFromJson(json);

  @override
  List<Object?> get props => [classId, occurrenceDate, attendees];
}
