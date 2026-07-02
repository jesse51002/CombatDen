import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'signup_response.g.dart';

/// Response for `POST /api/v1/signup`.
///
/// Mirrors the backend `SignupResponse`. [alreadySignedUp] is true on an
/// idempotent repeat (the member already had a sign-up for this occurrence)
/// — no new row was written and no extra capacity was consumed.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createToJson: false,
)
class SignupResponse extends Equatable {
  final String signupId;
  final bool alreadySignedUp;

  const SignupResponse({
    required this.signupId,
    required this.alreadySignedUp,
  });

  factory SignupResponse.fromJson(Map<String, dynamic> json) =>
      _$SignupResponseFromJson(json);

  @override
  List<Object?> get props => [signupId, alreadySignedUp];
}
