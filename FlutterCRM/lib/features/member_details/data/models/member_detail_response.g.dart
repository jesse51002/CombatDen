// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'member_detail_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

MemberDetailResponse _$MemberDetailResponseFromJson(
  Map<String, dynamic> json,
) => MemberDetailResponse(
  crmUserId: json['crm_user_id'] as String,
  gymId: json['gym_id'] as String,
  firstName: json['first_name'] as String,
  lastName: json['last_name'] as String,
  photoUrl: json['photo_url'] as String?,
  accountStatus: json['account_status'] as String?,
  membershipOverview: json['membership_overview'] as String,
  linkedToAccount: json['linked_to_account'] as String?,
  totalMembershipCount: (json['total_membership_count'] as num).toInt(),
  personalInfo: PersonalInfo.fromJson(
    json['personal_info'] as Map<String, dynamic>,
  ),
  linkedAccounts:
      (json['linked_accounts'] as List<dynamic>?)
          ?.map((e) => LinkedAccount.fromJson(e as Map<String, dynamic>))
          .toList() ??
      [],
  memberships:
      (json['memberships'] as List<dynamic>?)
          ?.map((e) => MembershipInfo.fromJson(e as Map<String, dynamic>))
          .toList() ??
      [],
  retention: Retention.fromJson(json['retention'] as Map<String, dynamic>),
  recentlyRedeemedRewards:
      (json['recently_redeemed_rewards'] as List<dynamic>?)
          ?.map((e) => RewardCardModel.fromJson(e as Map<String, dynamic>))
          .toList() ??
      [],
  paymentHistory:
      (json['payment_history'] as List<dynamic>?)
          ?.map((e) => PaymentRecord.fromJson(e as Map<String, dynamic>))
          .toList() ??
      [],
);
