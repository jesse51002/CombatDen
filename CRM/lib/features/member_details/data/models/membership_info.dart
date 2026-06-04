import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

import 'package:crm/features/member_details/data/models/discount_info.dart';
import 'package:crm/features/member_details/data/models/membership_member_info.dart';
import 'package:crm/features/member_details/data/models/paying_for_member.dart';
import 'package:crm/features/members_list/data/models/membership_status.dart';

part 'membership_info.g.dart';

/// Membership details including cost, dates, linked
/// accounts, and discounts.
///
/// Mirrors the merged `BillingMembershipInfo` schema.
/// `members` is keyed by `member_id`.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createToJson: false,
)
class MembershipInfo extends Equatable {
  /// Map of `member_id` → per-member row info (item id,
  /// end date, cancel date) for every covered family
  /// member on this plan. Use [itemIdFor] to resolve the
  /// `member_memberships.item_id` for a given member, and
  /// [exitDateFor] to surface a scheduled ending /
  /// cancellation date.
  @JsonKey(defaultValue: <String, MembershipMemberInfo>{})
  final Map<String, MembershipMemberInfo> members;

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
  final DateTime? freezeStartDate;
  final DateTime? freezeEndDate;
  @JsonKey(defaultValue: [])
  final List<PayingForMember> payingFor;
  @JsonKey(defaultValue: [])
  final List<DiscountInfo> discounts;

  const MembershipInfo({
    this.members = const {},
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

  /// Resolve the `member_memberships.item_id` for the
  /// given member on this plan. Returns null when the
  /// member is not covered, or when the backend has not
  /// populated [members].
  String? itemIdFor(String memberId) =>
      members[memberId]?.itemId;

  /// Scheduled cancel/end date for the given member, or
  /// null when the membership has no scheduled exit.
  MembershipExitDate? exitDateFor(String memberId) =>
      members[memberId]?.exitDate;

  /// True when the given member is still billed at a
  /// price that no longer matches the current plan cost.
  bool isOnOutdatedPriceFor(String memberId) =>
      members[memberId]?.onOutdatedPrice ?? false;

  @override
  List<Object?> get props => [
        members,
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
        freezeStartDate,
        freezeEndDate,
        payingFor,
        discounts,
      ];
}
