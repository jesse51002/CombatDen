import 'package:json_annotation/json_annotation.dart';

part 'member_identity.g.dart';

/// One member row the caller's verified email resolves to.
///
/// Mirrors `MemberPortalIdentity` in
/// `FastApiBackend/src/member_portal/schema/member_portal_schema.py`. The entry
/// point `GET /api/v1/member/members` returns a LIST of these because
/// `members.email` has no uniqueness constraint (a family shares one inbox), so
/// every other member-portal route takes the chosen [memberId] + [gymId]
/// explicitly.
@JsonSerializable(fieldRename: FieldRename.snake)
class MemberIdentity {
  final String memberId;
  final String gymId;
  final String gymName;
  final String? gymLogoUrl;
  final String? gymAddress;
  final String firstName;
  final String lastName;
  final String? photoUrl;

  const MemberIdentity({
    required this.memberId,
    required this.gymId,
    required this.gymName,
    required this.firstName,
    required this.lastName,
    this.gymLogoUrl,
    this.gymAddress,
    this.photoUrl,
  });

  /// The member's display name.
  String get fullName => '$firstName $lastName'.trim();

  factory MemberIdentity.fromJson(Map<String, dynamic> json) =>
      _$MemberIdentityFromJson(json);

  Map<String, dynamic> toJson() => _$MemberIdentityToJson(this);
}
