import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

import 'package:crm/features/member_details/data/models/card_on_file.dart';
import 'package:crm/features/member_details/data/models/linked_account.dart';
import 'package:crm/features/member_details/data/models/membership_info.dart';
import 'package:crm/features/member_details/data/models/pays_for_member.dart';
import 'package:crm/features/member_details/data/models/personal_info.dart';
import 'package:crm/features/member_details/data/models/rank.dart';
import 'package:crm/features/member_details/data/models/retention.dart';
import 'package:crm/features/member_details/data/models/reward_card_model.dart';

part 'member_detail_response.g.dart';

/// Full member detail for the Specific Member screen.
///
/// Mirrors the merged `MemberBillingDetailResponse`
/// schema returned by `GET /api/v1/members/{member_id}/billing`
/// — the billing-rich view that carries the member's
/// memberships, charges, card, linked accounts, rank, and
/// retention tree (member-id keyed).
///
/// Note: the merged contract splits member detail in two.
/// `GET /api/v1/members/{member_id}` returns a leaner
/// rank/retention-shaped `MemberDetailResponse`; this
/// class intentionally tracks the billing endpoint, which
/// is the one this feature's bloc + dialogs depend on.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createToJson: false,
)
class MemberDetailResponse extends Equatable {
  final String memberId;
  final String gymId;
  final String firstName;
  final String lastName;
  final String? photoUrl;
  final String? accountStatus;
  final String membershipOverview;
  final String? linkedToAccount;
  final int totalMonthlyRecurringPrice;
  final int totalMembershipCount;
  final PersonalInfo personalInfo;
  @JsonKey(defaultValue: [])
  final List<LinkedAccount> linkedAccounts;

  /// Every member (the viewed member included) whose recurring
  /// memberships this member funds — what a freeze on them would pause.
  @JsonKey(defaultValue: [])
  final List<PaysForMember> paysFor;
  @JsonKey(defaultValue: [])
  final List<MembershipInfo> memberships;
  final Retention retention;
  final Rank? rank;
  @JsonKey(defaultValue: [])
  final List<RewardCardModel> recentlyRedeemedRewards;
  final CardOnFile? cardOnFile;

  const MemberDetailResponse({
    required this.memberId,
    required this.gymId,
    required this.firstName,
    required this.lastName,
    this.photoUrl,
    this.accountStatus,
    required this.membershipOverview,
    this.linkedToAccount,
    required this.totalMonthlyRecurringPrice,
    required this.totalMembershipCount,
    required this.personalInfo,
    this.linkedAccounts = const [],
    this.paysFor = const [],
    this.memberships = const [],
    required this.retention,
    this.rank,
    this.recentlyRedeemedRewards = const [],
    this.cardOnFile,
  });

  factory MemberDetailResponse.fromJson(
    Map<String, dynamic> json,
  ) =>
      _$MemberDetailResponseFromJson(json);

  String get fullName => '$firstName $lastName';

  /// Whether the membership payment is current.
  bool get isPaid =>
      accountStatus?.toLowerCase() == 'paid';

  @override
  List<Object?> get props => [
        memberId,
        gymId,
        firstName,
        lastName,
        photoUrl,
        accountStatus,
        membershipOverview,
        linkedToAccount,
        totalMonthlyRecurringPrice,
        totalMembershipCount,
        personalInfo,
        linkedAccounts,
        paysFor,
        memberships,
        retention,
        rank,
        recentlyRedeemedRewards,
        cardOnFile,
      ];
}
