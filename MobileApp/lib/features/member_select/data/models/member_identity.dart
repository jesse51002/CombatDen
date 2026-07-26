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
///
/// The three gym CAPABILITY flags ride this identity read so the shell can be
/// composed before any feature fetch: they decide which bottom-nav tabs exist,
/// whether the rank UI renders at all, and which post-class cards are shown.
/// All three default to **true** when absent — a payload from an older build
/// (or an offline cache written by one) must not hide a feature the gym really
/// runs; an empty surface is recoverable, a missing one is invisible.
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

  /// Whether the gym runs a rank / belt ladder at all (`gyms.is_rank_enabled`).
  @JsonKey(defaultValue: true)
  final bool gymRankEnabled;

  /// Whether the gym has at least one ACTIVE reward.
  @JsonKey(defaultValue: true)
  final bool gymHasRewards;

  /// Whether the gym's video feed would serve at least one video.
  @JsonKey(defaultValue: true)
  final bool gymHasVideos;

  const MemberIdentity({
    required this.memberId,
    required this.gymId,
    required this.gymName,
    required this.firstName,
    required this.lastName,
    this.gymLogoUrl,
    this.gymAddress,
    this.photoUrl,
    this.gymRankEnabled = true,
    this.gymHasRewards = true,
    this.gymHasVideos = true,
  });

  /// The member's display name.
  String get fullName => '$firstName $lastName'.trim();

  factory MemberIdentity.fromJson(Map<String, dynamic> json) =>
      _$MemberIdentityFromJson(json);

  Map<String, dynamic> toJson() => _$MemberIdentityToJson(this);
}
