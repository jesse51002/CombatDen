import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

import 'package:crm/features/member_details/data/models/membership_info.dart';
import 'package:crm/features/member_details/data/models/payment_record.dart';
import 'package:crm/features/member_details/data/models/personal_info.dart';
import 'package:crm/features/member_details/data/models/rank_retention.dart';
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
  final String firstName;
  final String lastName;
  final String? photoUrl;
  final String? accountStatus;
  final PersonalInfo personalInfo;
  final MembershipInfo membership;
  final RankRetention rankRetention;
  @JsonKey(defaultValue: [])
  final List<RewardCardModel> recentlyRedeemedRewards;
  @JsonKey(defaultValue: [])
  final List<PaymentRecord> paymentHistory;

  const MemberDetailResponse({
    required this.crmUserId,
    required this.firstName,
    required this.lastName,
    this.photoUrl,
    this.accountStatus,
    required this.personalInfo,
    required this.membership,
    required this.rankRetention,
    this.recentlyRedeemedRewards = const [],
    this.paymentHistory = const [],
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
        firstName,
        lastName,
        photoUrl,
        accountStatus,
        personalInfo,
        membership,
        rankRetention,
        recentlyRedeemedRewards,
        paymentHistory,
      ];
}
