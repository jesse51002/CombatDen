// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'member_profile.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

MemberProfile _$MemberProfileFromJson(Map<String, dynamic> json) =>
    MemberProfile(
      memberId: json['member_id'] as String,
      gymId: json['gym_id'] as String,
      firstName: json['first_name'] as String,
      lastName: json['last_name'] as String,
      personalInfo: BillingPersonalInfo.fromJson(
        json['personal_info'] as Map<String, dynamic>,
      ),
      retention: BillingRetention.fromJson(
        json['retention'] as Map<String, dynamic>,
      ),
      photoUrl: json['photo_url'] as String?,
      rank: json['rank'] == null
          ? null
          : BillingRank.fromJson(json['rank'] as Map<String, dynamic>),
      memberships:
          (json['memberships'] as List<dynamic>?)
              ?.map(
                (e) =>
                    BillingMembershipInfo.fromJson(e as Map<String, dynamic>),
              )
              .toList() ??
          [],
      recentlyRedeemedRewards:
          (json['recently_redeemed_rewards'] as List<dynamic>?)
              ?.map(
                (e) => BillingRewardCard.fromJson(e as Map<String, dynamic>),
              )
              .toList() ??
          [],
      pendingRedemptions:
          (json['pending_redemptions'] as List<dynamic>?)
              ?.map(
                (e) =>
                    PendingRedemptionCard.fromJson(e as Map<String, dynamic>),
              )
              .toList() ??
          [],
    );
