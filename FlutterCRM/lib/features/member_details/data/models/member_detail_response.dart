import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

import 'package:crm/features/member_details/data/models/card_on_file.dart';
import 'package:crm/features/member_details/data/models/linked_account.dart';
import 'package:crm/features/member_details/data/models/membership_info.dart';
import 'package:crm/features/member_details/data/models/payment_record.dart';
import 'package:crm/features/member_details/data/models/personal_info.dart';
import 'package:crm/features/member_details/data/models/retention.dart';
import 'package:crm/features/member_details/data/models/reward_card_model.dart';

part 'member_detail_response.g.dart';

/// Full member detail response for the Specific Member
/// screen.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createToJson: false,
)
class MemberDetailResponse extends Equatable {
  final String crmUserId;
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
  @JsonKey(defaultValue: [])
  final List<MembershipInfo> memberships;
  final Retention retention;
  @JsonKey(defaultValue: [])
  final List<RewardCardModel> recentlyRedeemedRewards;
  @JsonKey(defaultValue: [])
  final List<PaymentRecord> paymentHistory;
  final CardOnFile? cardOnFile;

  const MemberDetailResponse({
    required this.crmUserId,
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
    this.memberships = const [],
    required this.retention,
    this.recentlyRedeemedRewards = const [],
    this.paymentHistory = const [],
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
        crmUserId,
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
        memberships,
        retention,
        recentlyRedeemedRewards,
        paymentHistory,
        cardOnFile,
      ];
}
