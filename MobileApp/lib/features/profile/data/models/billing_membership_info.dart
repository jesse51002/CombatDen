import 'package:json_annotation/json_annotation.dart';

import 'package:mobile_app/features/profile/data/models/member_membership_applied_discount.dart';

part 'billing_membership_info.g.dart';

/// A membership plan's billing type. Mirrors `PlanType` in
/// `Database/python_data/schema/membership_plan.py`.
enum PlanType {
  @JsonValue('trial')
  trial,
  @JsonValue('one_time')
  oneTime,
  @JsonValue('recurring')
  recurring,
  unknown,
}

/// A computed membership status. Mirrors `CrmMemberStatus` in
/// `FastApiBackend/src/members/schema/members_crm_members_list_schema.py`.
enum CrmMemberStatus {
  @JsonValue('active')
  active,
  @JsonValue('trial')
  trial,
  @JsonValue('frozen')
  frozen,
  @JsonValue('cancelled')
  cancelled,
  @JsonValue('ended')
  ended,
  @JsonValue('overdue')
  overdue,
  unknown,
}

/// One of the member's own memberships.
///
/// Mirrors `BillingMembershipInfo` in
/// `FastApiBackend/src/members/schema/members_billing_schema.py` (reused
/// verbatim by the member-portal profile). Money fields are signed integer
/// minor units (cents). Date fields stay raw ISO strings (display-only).
@JsonSerializable(fieldRename: FieldRename.snake, createToJson: false)
class BillingMembershipInfo {
  final String planId;
  final String planName;
  @JsonKey(unknownEnumValue: PlanType.unknown)
  final PlanType? planType;
  @JsonKey(unknownEnumValue: CrmMemberStatus.unknown)
  final CrmMemberStatus status;
  final String itemId;
  final String paidByMemberId;
  final int baseCost;
  final int? currentActivePrice;
  @JsonKey(defaultValue: false)
  final bool onOutdatedPrice;
  final int durationAmount;
  final String durationUnit;
  final int totalPrice;
  final String? lastPaidDate;
  final String? nextDueDate;
  final String startDate;
  final String? endDate;
  final String? cancelDate;
  final String? freezeStartDate;
  final String? freezeEndDate;
  final int? classCount;
  @JsonKey(defaultValue: 0)
  final int classesUsed;
  final int? classesRemaining;
  @JsonKey(defaultValue: <MemberMembershipAppliedDiscount>[])
  final List<MemberMembershipAppliedDiscount> discounts;

  const BillingMembershipInfo({
    required this.planId,
    required this.planName,
    required this.status,
    required this.itemId,
    required this.paidByMemberId,
    required this.baseCost,
    required this.durationAmount,
    required this.durationUnit,
    required this.totalPrice,
    required this.startDate,
    this.planType,
    this.currentActivePrice,
    this.onOutdatedPrice = false,
    this.lastPaidDate,
    this.nextDueDate,
    this.endDate,
    this.cancelDate,
    this.freezeStartDate,
    this.freezeEndDate,
    this.classCount,
    this.classesUsed = 0,
    this.classesRemaining,
    this.discounts = const [],
  });

  factory BillingMembershipInfo.fromJson(Map<String, dynamic> json) =>
      _$BillingMembershipInfoFromJson(json);
}
