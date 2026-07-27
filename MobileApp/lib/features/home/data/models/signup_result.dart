import 'package:json_annotation/json_annotation.dart';

part 'signup_result.g.dart';

/// Result of reserving a member's spot on an occurrence.
///
/// Mirrors `SignupResponse` in
/// `FastApiBackend/src/checkin/schema/signup_schema.py`
/// (`POST /api/v1/member/gyms/{gid}/members/{mid}/signup`). An idempotent
/// repeat returns the existing `signup_id` with [alreadySignedUp] true and a
/// 200 — the booking bloc treats that as success (no capacity consumed).
@JsonSerializable(fieldRename: FieldRename.snake, createToJson: false)
class SignupResult {
  final String signupId;
  final bool alreadySignedUp;

  const SignupResult({
    required this.signupId,
    required this.alreadySignedUp,
  });

  factory SignupResult.fromJson(Map<String, dynamic> json) =>
      _$SignupResultFromJson(json);
}

/// Result of cancelling a member's reservation.
///
/// Mirrors `SignupRemoveResponse` in
/// `FastApiBackend/src/checkin/schema/signup_schema.py`
/// (`DELETE …/signup`). [removed] is false (still a 200) when there was no
/// reservation to cancel.
@JsonSerializable(fieldRename: FieldRename.snake, createToJson: false)
class SignupRemoveResult {
  final bool removed;

  const SignupRemoveResult({required this.removed});

  factory SignupRemoveResult.fromJson(Map<String, dynamic> json) =>
      _$SignupRemoveResultFromJson(json);
}
