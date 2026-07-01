import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'check_in_request.g.dart';

/// Body for the single check-in (`POST /api/v1/checkin`).
///
/// Mirrors the backend `CheckinRequest`. The occurrence is addressed by
/// [classId] + [occurrenceDate] (a gym-local `YYYY-MM-DD` date string — sent as
/// a bare date, never an ISO datetime). [isMember] selects the gate: the CRM is
/// the STAFF surface, so it is always `false` — a clean check-in is recorded,
/// but one that hits a gate warning is held for confirmation (nothing
/// written; see `CheckInResponse.requiresConfirmation`) unless [ignoreWarnings]
/// overrides — resend the identical body with it `true` to record through the
/// warnings (the "Check in anyway" override).
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
  final bool ignoreWarnings;

  const CheckInRequest({
    required this.memberId,
    required this.gymId,
    required this.classId,
    required this.occurrenceDate,
    this.isMember = false,
    this.ignoreWarnings = false,
  });

  Map<String, dynamic> toJson() => _$CheckInRequestToJson(this);

  @override
  List<Object?> get props =>
      [memberId, gymId, classId, occurrenceDate, isMember, ignoreWarnings];
}
