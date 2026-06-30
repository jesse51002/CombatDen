import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'batch_check_in_request.g.dart';

/// Body for the batch check-in (`POST /api/v1/checkin/batch`).
///
/// Mirrors the backend `BatchCheckinRequest`. The occurrence is addressed by
/// the [classId] + [occurrenceDate] BODY fields (a gym-local `YYYY-MM-DD` date
/// string); the body also carries the gym (auth gate), the members to check in,
/// and [isMember]. The CRM is the STAFF surface, so [isMember] is always
/// `false` — every member is recorded and gate conditions come back as
/// non-blocking `warnings`.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createFactory: false,
)
class BatchCheckInRequest extends Equatable {
  final String gymId;
  final String classId;
  final String occurrenceDate;
  final List<String> memberIds;
  final bool isMember;

  const BatchCheckInRequest({
    required this.gymId,
    required this.classId,
    required this.occurrenceDate,
    required this.memberIds,
    this.isMember = false,
  });

  Map<String, dynamic> toJson() => _$BatchCheckInRequestToJson(this);

  @override
  List<Object?> get props =>
      [gymId, classId, occurrenceDate, memberIds, isMember];
}
