import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'signup_request.g.dart';

/// Body for `POST /api/v1/signup` — reserve a member a spot on a class
/// occurrence (a reservation, NOT attendance).
///
/// Mirrors the backend `SignupRequest`
/// (`../FastApiBackend/src/checkin/schema/signup_schema.py`).
/// [occurrenceDate] is a bare `YYYY-MM-DD` gym-local date string.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createFactory: false,
)
class SignupRequest extends Equatable {
  final String memberId;
  final String gymId;
  final String classId;
  final String occurrenceDate;

  const SignupRequest({
    required this.memberId,
    required this.gymId,
    required this.classId,
    required this.occurrenceDate,
  });

  Map<String, dynamic> toJson() => _$SignupRequestToJson(this);

  @override
  List<Object?> get props => [memberId, gymId, classId, occurrenceDate];
}
