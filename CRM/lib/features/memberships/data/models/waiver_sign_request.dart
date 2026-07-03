import 'package:json_annotation/json_annotation.dart';

part 'waiver_sign_request.g.dart';

/// Body for `POST /api/v1/waivers/{waiver_id}/signatures`.
///
/// The client echoes [waiverVersionId] — the version id it displayed — so the
/// backend can reject a stale version (409) when the gym published a newer one
/// between the load and the sign (closing the read-then-sign race).
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createFactory: false,
)
class WaiverSignRequest {
  final String gymId;
  final String memberId;
  final String waiverVersionId;
  final String signerName;

  /// Always true — [json_serializable] serializes `true` literally;
  /// the backend's `Literal[True]` validator rejects anything else.
  final bool consentAcknowledged;

  const WaiverSignRequest({
    required this.gymId,
    required this.memberId,
    required this.waiverVersionId,
    required this.signerName,
    this.consentAcknowledged = true,
  });

  Map<String, dynamic> toJson() => _$WaiverSignRequestToJson(this);
}
