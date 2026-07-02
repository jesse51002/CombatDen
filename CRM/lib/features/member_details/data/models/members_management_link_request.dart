import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'members_management_link_request.g.dart';

/// Body for `PUT /api/v1/members/{member_id}/link`.
///
/// Mirrors the backend `MembersBillingLinkRequest`: authorizes [payerMemberId]
/// to pay for the path member. The payer signs the gym's default
/// authorized-payer waiver in the same call — [waiverVersionId] is the version
/// the UI displayed (echoed back so the backend can version-lock and reject a
/// stale version on 409), [signerName] is the typed signature, and
/// [consentAcknowledged] must be true. The signature + the authorization are
/// recorded atomically server-side.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createFactory: false,
)
class MembersManagementLinkRequest extends Equatable {
  final String payerMemberId;
  final String waiverVersionId;
  final String signerName;
  final bool consentAcknowledged;

  const MembersManagementLinkRequest({
    required this.payerMemberId,
    required this.waiverVersionId,
    required this.signerName,
    required this.consentAcknowledged,
  });

  Map<String, dynamic> toJson() =>
      _$MembersManagementLinkRequestToJson(this);

  @override
  @JsonKey(includeToJson: false)
  List<Object?> get props =>
      [payerMemberId, waiverVersionId, signerName, consentAcknowledged];

  @override
  @JsonKey(includeToJson: false)
  bool? get stringify => super.stringify;

  @override
  @JsonKey(includeToJson: false)
  int get hashCode => super.hashCode; // ignore: hash_and_equals
}
