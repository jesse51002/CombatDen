import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'signup_request.g.dart';

/// Body for `POST /api/v1/signup` — reserve a member a spot on a class
/// occurrence (a reservation, NOT attendance).
///
/// Mirrors the backend `SignupRequest`
/// (`../FastApiBackend/src/checkin/schema/signup_schema.py`).
/// [occurrenceDate] + [occurrenceTime] are the occurrence's identity key
/// (bare `YYYY-MM-DD` / `HH:MM:SS` gym-local strings — several slots per day
/// are legal, so both name the exact occurrence).
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createFactory: false,
)
class SignupRequest extends Equatable {
  final String memberId;
  final String gymId;
  final String classId;
  final String occurrenceDate;
  final String occurrenceTime;

  const SignupRequest({
    required this.memberId,
    required this.gymId,
    required this.classId,
    required this.occurrenceDate,
    required this.occurrenceTime,
  });

  Map<String, dynamic> toJson() => _$SignupRequestToJson(this);

  @override
  List<Object?> get props =>
      [memberId, gymId, classId, occurrenceDate, occurrenceTime];
}
