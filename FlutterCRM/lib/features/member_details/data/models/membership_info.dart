import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

import 'package:crm/features/member_details/data/models/discount_info.dart';
import 'package:crm/features/member_details/data/models/paying_for_member.dart';
import 'package:crm/features/members_list/data/models/membership_status.dart';

part 'membership_info.g.dart';

/// Membership details including cost, dates, linked
/// accounts, and discounts.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createToJson: false,
)
class MembershipInfo extends Equatable {
  final String planId;
  final String planName;
  final String? planType;
  @JsonKey(fromJson: MembershipStatus.fromJson)
  final MembershipStatus status;
  final int baseCost;
  final int durationAmount;
  final String durationUnit;
  final int totalPrice;
  final DateTime? lastPaidDate;
  final DateTime? nextDueDate;
  final DateTime startDate;
  final DateTime? endDate;
  final DateTime? freezeStartDate;
  final DateTime? freezeEndDate;
  @JsonKey(defaultValue: [])
  final List<PayingForMember> payingFor;
  @JsonKey(defaultValue: [])
  final List<DiscountInfo> discounts;

  const MembershipInfo({
    required this.planId,
    required this.planName,
    this.planType,
    required this.status,
    required this.baseCost,
    required this.durationAmount,
    required this.durationUnit,
    required this.totalPrice,
    this.lastPaidDate,
    this.nextDueDate,
    required this.startDate,
    this.endDate,
    this.freezeStartDate,
    this.freezeEndDate,
    this.payingFor = const [],
    this.discounts = const [],
  });

  factory MembershipInfo.fromJson(
    Map<String, dynamic> json,
  ) =>
      _$MembershipInfoFromJson(json);

  /// Display name for the membership plan.
  String get displayName => planName;

  @override
  List<Object?> get props => [
        planId,
        planName,
        planType,
        status,
        baseCost,
        durationAmount,
        durationUnit,
        totalPrice,
        lastPaidDate,
        nextDueDate,
        startDate,
        endDate,
        freezeStartDate,
        freezeEndDate,
        payingFor,
        discounts,
      ];
}
