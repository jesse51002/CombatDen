import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'check_in_request.g.dart';

/// Body for the single check-in (`POST /api/v1/checkin`).
///
/// Mirrors the backend `CheckinRequest`. The occurrence is addressed by
/// [classId] + [occurrenceDate] (a gym-local `YYYY-MM-DD` date string — sent as
/// a bare date, never an ISO datetime). [isMember] selects the gate: the CRM is
/// the STAFF surface, so it is always `false` — the check-in is ALWAYS recorded
/// and any gate conditions come back as non-blocking `warnings`.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createFactory: false,
)
class CheckInRequest extends Equatable {
  final String memberId;
  final String gymId;
  final String classId;
  final String occurrenceDate;
  final bool isMember;

  const CheckInRequest({
    required this.memberId,
    required this.gymId,
    required this.classId,
    required this.occurrenceDate,
    this.isMember = false,
  });

  Map<String, dynamic> toJson() => _$CheckInRequestToJson(this);

  @override
  List<Object?> get props =>
      [memberId, gymId, classId, occurrenceDate, isMember];
}
