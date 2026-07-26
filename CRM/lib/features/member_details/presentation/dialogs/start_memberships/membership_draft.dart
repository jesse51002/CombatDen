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

  /// One-time / trial purchase count from the stepper. Sent
  /// as the wire item's `quantity` (ONE item of `quantity =
  /// count`, not N copies). Always 1 for recurring (no
  /// stepper).
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

  /// This draft with [discountId] toggled in or out of
  /// the preset picks.
  MembershipDraft withPresetToggled(String discountId) {
    final ids = Set<String>.from(discountIds);
    if (!ids.remove(discountId)) {
      ids.add(discountId);
    }
    return copyWith(discountIds: ids);
  }

  /// This draft with [value] appended to the customs.
  MembershipDraft withCustomAdded(DiscountValue value) =>
      copyWith(
        customDiscounts: [...customDiscounts, value],
      );

  /// This draft with the custom at [index] removed.
  MembershipDraft withCustomRemovedAt(int index) {
    final customs = List.of(customDiscounts)
      ..removeAt(index);
    return copyWith(customDiscounts: customs);
  }

  /// Whether any discount (preset or custom) is added.
  bool get hasDiscounts =>
      discountIds.isNotEmpty || customDiscounts.isNotEmpty;

  /// The wire item for this draft (carrying [count] as
  /// `quantity`), or null when the plan has no active price
  /// (it shouldn't be selectable).
  MemberMembershipsStartItem? toItem(String memberId) {
    final priceId = plan.activePrice?.priceId;
    if (priceId == null) return null;
    return MemberMembershipsStartItem(
      memberId: memberId,
      priceId: priceId,
      quantity: count,
      discountIds: discountIds.toList(),
      customDiscounts: customDiscounts,
    );
  }
}
