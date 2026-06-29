import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'check_in_request.g.dart';

/// Body for the single staff check-in (`POST /api/v1/classes/checkin`).
///
/// Mirrors the backend `CheckinRequest`. The occurrence is addressed by
/// [classId] + [occurrenceDate] (a gym-local `YYYY-MM-DD` date string — sent as
/// a bare date, never an ISO datetime). [allowOverride] forces the check-in
/// past the eligibility, punch-card, and room-capacity gates.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createFactory: false,
)
class CheckInRequest extends Equatable {
  final String memberId;
  final String gymId;
  final String classId;
  final String occurrenceDate;
  final bool allowOverride;

  const CheckInRequest({
    required this.memberId,
    required this.gymId,
    required this.classId,
    required this.occurrenceDate,
    this.allowOverride = false,
  });

  Map<String, dynamic> toJson() => _$CheckInRequestToJson(this);

  @override
  List<Object?> get props =>
      [memberId, gymId, classId, occurrenceDate, allowOverride];
}
