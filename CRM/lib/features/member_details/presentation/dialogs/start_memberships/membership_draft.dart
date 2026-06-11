import 'package:crm/features/member_details/data/models/discount_response.dart';
import 'package:crm/features/member_details/data/models/discount_value.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_item.dart';
import 'package:crm/features/member_details/data/models/membership_plan_response.dart';

/// One picked membership for one member, as configured by
/// the wizard: the plan (its active price drives the wire
/// `price_id`), the one_time/trial purchase count, and the
/// discounts (preset ids + inline custom values) gathered
/// on the discounts step.
class MembershipDraft {
  final MembershipPlanResponse plan;

  /// One-time / trial purchase count from the stepper.
  /// UI-only today — [toItem] always emits ONE item.
  // TODO(known placeholder): count is display-only — the
  // backend rejects duplicate (member, price) items until
  // PaymentRefactor.md §10 ships, when count N maps to N
  // duplicate items in `memberships`. DELETE this comment
  // (and the single-item cap in toItem) when implemented.
  final int count;

  /// Preset discount ids picked for this membership.
  final Set<String> discountIds;

  /// Inline custom discount values for this membership
  /// (minted server-side as one-shot customs).
  final List<DiscountValue> customDiscounts;

  const MembershipDraft({
    required this.plan,
    this.count = 1,
    this.discountIds = const {},
    this.customDiscounts = const [],
  });

  MembershipDraft copyWith({
    int? count,
    Set<String>? discountIds,
    List<DiscountValue>? customDiscounts,
  }) {
    return MembershipDraft(
      plan: plan,
      count: count ?? this.count,
      discountIds: discountIds ?? this.discountIds,
      customDiscounts:
          customDiscounts ?? this.customDiscounts,
    );
  }

  /// Whether any discount (preset or custom) is added.
  bool get hasDiscounts =>
      discountIds.isNotEmpty || customDiscounts.isNotEmpty;

  /// UI estimate of this membership's price after the added
  /// discounts, in cents: percents apply first (compounding
  /// sequentially), then dollar amounts subtract, floored at
  /// zero — mirroring the backend's percent→dollar coupon
  /// order. The Preview step stays the authoritative figure.
  int discountedPriceCents(List<DiscountResponse> presets) {
    final base = plan.activePrice?.price ?? 0;
    final values = <DiscountValue>[
      for (final id in discountIds)
        for (final d in presets)
          if (d.discountId == id) d.value,
      ...customDiscounts,
    ];
    var price = base.toDouble();
    for (final v in values) {
      final pct = v.percentageOff;
      if (pct != null) price *= 1 - pct / 100;
    }
    var cents = price.round();
    for (final v in values) {
      final dollars = v.dollarOff;
      if (dollars != null) cents -= dollars;
    }
    return cents < 0 ? 0 : cents;
  }

  /// The wire item for this draft, or null when the plan
  /// has no active price (it shouldn't be selectable).
  MemberMembershipsStartItem? toItem(String memberId) {
    final priceId = plan.activePrice?.priceId;
    if (priceId == null) return null;
    return MemberMembershipsStartItem(
      memberId: memberId,
      priceId: priceId,
      discountIds: discountIds.toList(),
      customDiscounts: customDiscounts,
    );
  }
}
