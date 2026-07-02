import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'batch_check_in_request.g.dart';

/// Body for the batch check-in (`POST /api/v1/checkin/batch`).
///
/// Mirrors the backend `BatchCheckinRequest`. The occurrence is addressed by
/// the [classId] + [occurrenceDate] + [occurrenceTime] BODY fields — its full
/// identity key (gym-local `YYYY-MM-DD` / `HH:MM:SS` strings — several slots
/// per day are legal, so both name the exact occurrence); the body also
/// carries the gym (auth gate), the members to check in, and [isMember]. The
/// CRM is the STAFF surface, so [isMember] is always `false` — a clean member
/// is recorded; a member the gate warns on is held as `needs_confirmation`
/// (nothing written) unless [ignoreWarnings] overrides — resend a batch of
/// just those member ids with it `true` to record them through the warnings
/// (the "Check in anyway" override).
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createFactory: false,
)
class BatchCheckInRequest extends Equatable {
  final String gymId;
  final String classId;
  final String occurrenceDate;
  final String occurrenceTime;
  final List<String> memberIds;
  final bool isMember;
  final bool ignoreWarnings;

  const BatchCheckInRequest({
    required this.gymId,
    required this.classId,
    required this.occurrenceDate,
    required this.occurrenceTime,
    required this.memberIds,
    this.isMember = false,
    this.ignoreWarnings = false,
  });

  Map<String, dynamic> toJson() => _$BatchCheckInRequestToJson(this);

  @override
  List<Object?> get props => [
        gymId,
        classId,
        occurrenceDate,
        occurrenceTime,
        memberIds,
        isMember,
        ignoreWarnings,
      ];
}
