import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

import 'package:crm/features/member_details/data/models/discount_info.dart';
import 'package:crm/features/member_details/data/models/linked_account.dart';
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
  final double baseCost;
  final String billingCycle;
  final double totalCost;
  final String? costFormula;
  final double? additionalMemberDiscount;
  final DateTime? lastPaidDate;
  final DateTime? nextDueDate;
  final DateTime startDate;
  @JsonKey(defaultValue: [])
  final List<LinkedAccount> payingFor;
  @JsonKey(defaultValue: [])
  final List<DiscountInfo> discounts;

  const MembershipInfo({
    required this.planId,
    required this.planName,
    this.planType,
    required this.status,
    required this.baseCost,
    required this.billingCycle,
    required this.totalCost,
    this.costFormula,
    this.additionalMemberDiscount,
    this.lastPaidDate,
    this.nextDueDate,
    required this.startDate,
    this.payingFor = const [],
    this.discounts = const [],
  });

  factory MembershipInfo.fromJson(
    Map<String, dynamic> json,
  ) =>
      _$MembershipInfoFromJson(json);

  /// Display name combining plan name and type.
  String get displayName {
    if (planType != null && planType!.isNotEmpty) {
      return '$planName ($planType)';
    }
    return planName;
  }

  @override
  List<Object?> get props => [
        planId,
        planName,
        planType,
        status,
        baseCost,
        billingCycle,
        totalCost,
        costFormula,
        additionalMemberDiscount,
        lastPaidDate,
        nextDueDate,
        startDate,
        payingFor,
        discounts,
      ];
}
