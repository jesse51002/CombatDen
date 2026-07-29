import 'package:json_annotation/json_annotation.dart';

import 'package:mobile_app/features/profile/data/models/billing_membership_info.dart';
import 'package:mobile_app/features/profile/data/models/billing_personal_info.dart';
import 'package:mobile_app/features/profile/data/models/billing_rank.dart';
import 'package:mobile_app/features/profile/data/models/billing_retention.dart';
import 'package:mobile_app/features/profile/data/models/billing_reward_card.dart';
import 'package:mobile_app/features/profile/data/models/pending_redemption_card.dart';

part 'member_profile.g.dart';

/// The member's own profile — the app's shared source for the topbar's
/// streak / points, plus the rank block, membership cards, and reward
/// redemptions later features read.
///
/// Mirrors `MemberPortalProfile` in
/// `FastApiBackend/src/member_portal/schema/member_portal_schema.py`
/// (`GET /api/v1/member/gyms/{gid}/members/{mid}`). Its per-block sub-models
/// are the same ones the CRM member-detail surface uses, so the two surfaces
/// can't disagree about what a card or a rank looks like.
@JsonSerializable(fieldRename: FieldRename.snake, createToJson: false)
class MemberProfile {
  final String memberId;
  final String gymId;
  final String firstName;
  final String lastName;
  final String? photoUrl;
  final BillingPersonalInfo personalInfo;
  final BillingRetention retention;
  final BillingRank? rank;
  @JsonKey(defaultValue: <BillingMembershipInfo>[])
  final List<BillingMembershipInfo> memberships;
  @JsonKey(defaultValue: <BillingRewardCard>[])
  final List<BillingRewardCard> recentlyRedeemedRewards;
  @JsonKey(defaultValue: <PendingRedemptionCard>[])
  final List<PendingRedemptionCard> pendingRedemptions;

  const MemberProfile({
    required this.memberId,
    required this.gymId,
    required this.firstName,
    required this.lastName,
    required this.personalInfo,
    required this.retention,
    this.photoUrl,
    this.rank,
    this.memberships = const [],
    this.recentlyRedeemedRewards = const [],
    this.pendingRedemptions = const [],
  });

  factory MemberProfile.fromJson(Map<String, dynamic> json) =>
      _$MemberProfileFromJson(json);
}
