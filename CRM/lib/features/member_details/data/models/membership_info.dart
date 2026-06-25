import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

import 'package:crm/features/member_details/data/models/discount_info.dart';
import 'package:crm/features/members_list/data/models/membership_status.dart';

part 'membership_info.g.dart';

/// One membership in the member-detail carousel.
///
/// Mirrors the backend `BillingMembershipInfo`. The carousel is scoped to the
/// viewed member and the backend returns one row per membership, so each card
/// is exactly one of the viewed member's own memberships — there is no
/// cross-member grouping. Every field is flat: [itemId] is the
/// `member_memberships` row id used by per-membership mutations, [paidByMemberId]
/// is the payer (the member themselves, or an authorized payer), and the
/// class-usage trio is this member's usage for the current cycle.
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

  /// ID of the underlying `member_memberships` row — the handle used by
  /// per-membership mutations (cancel, update price, mark-paid-cash, discount
  /// add/remove).
  final String itemId;

  /// The PAYER of this membership — whose Stripe customer / subscription bills
  /// it: the viewed member (self-pay) or an authorized payer. Drives the card's
  /// "Paid by" row.
  final String paidByMemberId;

  /// This membership's own pinned price (minor units), before discounts.
  final int baseCost;

  /// The plan's current active price (minor units), or null when the plan has
  /// no active price. Used to show the "migrate to current price" prompt when
  /// this membership is on an older pinned price.
  final int? currentActivePrice;

  /// True when this membership is still billed at a price that no longer
  /// matches the current plan cost (the plan price changed but it was not
  /// migrated).
  @JsonKey(defaultValue: false)
  final bool onOutdatedPrice;

  final int durationAmount;
  final String durationUnit;

  /// This membership's own after-discount total (minor units).
  final int totalPrice;
  final DateTime? lastPaidDate;
  final DateTime? nextDueDate;
  final DateTime startDate;

  /// Natural end date of the membership (e.g. the final day of a one-time
  /// pass). Null for recurring plans with no scheduled end.
  final DateTime? endDate;

  /// Effective cancellation date — access ends after this day. Set once staff
  /// cancel the membership; null while it is still active.
  final DateTime? cancelDate;

  final DateTime? freezeStartDate;
  final DateTime? freezeEndDate;

  /// This member's class usage for the current cycle (null / 0 when absent).
  final int? classCount;
  @JsonKey(defaultValue: 0)
  final int classesUsed;
  final int? classesRemaining;

  @JsonKey(defaultValue: [])
  final List<DiscountInfo> discounts;

  const MembershipInfo({
    required this.planId,
    required this.planName,
    this.planType,
    required this.status,
    required this.itemId,
    required this.paidByMemberId,
    required this.baseCost,
    this.currentActivePrice,
    this.onOutdatedPrice = false,
    required this.durationAmount,
    required this.durationUnit,
    required this.totalPrice,
    this.lastPaidDate,
    this.nextDueDate,
    required this.startDate,
    this.endDate,
    this.cancelDate,
    this.freezeStartDate,
    this.freezeEndDate,
    this.classCount,
    this.classesUsed = 0,
    this.classesRemaining,
    this.discounts = const [],
  });

  factory MembershipInfo.fromJson(
    Map<String, dynamic> json,
  ) =>
      _$MembershipInfoFromJson(json);

  /// Display name for the membership plan.
  String get displayName => planName;

  /// The soonest upcoming exit date for this membership — the earlier of
  /// [cancelDate] and [endDate] — along with which kind it is. Returns null
  /// when neither is set.
  MembershipExitDate? get exitDate {
    final c = cancelDate;
    final e = endDate;
    if (c == null && e == null) return null;
    if (c == null) {
      return MembershipExitDate(
        date: e!,
        kind: MembershipExitKind.ending,
      );
    }
    if (e == null) {
      return MembershipExitDate(
        date: c,
        kind: MembershipExitKind.cancelling,
      );
    }
    return c.isBefore(e)
        ? MembershipExitDate(
            date: c,
            kind: MembershipExitKind.cancelling,
          )
        : MembershipExitDate(
            date: e,
            kind: MembershipExitKind.ending,
          );
  }

  @override
  List<Object?> get props => [
        planId,
        planName,
        planType,
        status,
        itemId,
        paidByMemberId,
        baseCost,
        currentActivePrice,
        onOutdatedPrice,
        durationAmount,
        durationUnit,
        totalPrice,
        lastPaidDate,
        nextDueDate,
        startDate,
        endDate,
        cancelDate,
        freezeStartDate,
        freezeEndDate,
        classCount,
        classesUsed,
        classesRemaining,
        discounts,
      ];
}

enum MembershipExitKind { cancelling, ending }

class MembershipExitDate extends Equatable {
  final DateTime date;
  final MembershipExitKind kind;

  const MembershipExitDate({
    required this.date,
    required this.kind,
  });

  @override
  List<Object?> get props => [date, kind];
}
