import 'package:equatable/equatable.dart';

import 'package:crm/features/member_details/data/models/discount_value.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_item.dart';
import 'package:crm/features/member_details/data/models/membership_plan_response.dart';

/// One picked membership for one person, as the desk configures it: the plan
/// (whose active price drives the wire `price_id`), the pack purchase count,
/// and the discounts attached INLINE on the plans step.
///
/// The discounts live on the draft rather than on a step of their own — a
/// price reduction is a property of the membership being sold, and pulling it
/// into a separate walk made staff answer "which plan" and "what does it cost"
/// on two different screens.
class MembershipWizardDraft extends Equatable {
  final MembershipPlanResponse plan;

  /// The one_time / trial purchase count, sent as the wire item's `quantity`
  /// (ONE item of `quantity = N`, never N copies). Always 1 for a recurring
  /// plan — `trg_recurring_quantity_must_be_one` refuses anything else, so the
  /// value is pinned where it is SET rather than trusted to a stepper's
  /// visibility.
  final int quantity;

  /// Preset discount ids picked for this membership.
  final Set<String> presetIds;

  /// Inline one-off discount values for this membership, minted server-side as
  /// single-use `custom` rows at creation.
  final List<DiscountValue> customs;

  const MembershipWizardDraft({
    required this.plan,
    this.quantity = 1,
    this.presetIds = const {},
    this.customs = const [],
  });

  MembershipWizardDraft copyWith({
    int? quantity,
    Set<String>? presetIds,
    List<DiscountValue>? customs,
  }) =>
      MembershipWizardDraft(
        plan: plan,
        quantity: quantity ?? this.quantity,
        presetIds: presetIds ?? this.presetIds,
        customs: customs ?? this.customs,
      );

  /// Whether anything reduces this membership's price.
  bool get hasDiscounts => presetIds.isNotEmpty || customs.isNotEmpty;

  /// This membership's undiscounted LINE base, in minor units — the unit price
  /// times the pack count. Null when the plan carries no active price (which
  /// the catalogue filter already excludes from sale).
  int? get lineBaseMinorUnits {
    final price = plan.activePrice?.price;
    return price == null ? null : price * quantity;
  }

  /// The wire item for this draft, or null when the plan has no active price.
  MemberMembershipsStartItem? toItem(String memberId) {
    final priceId = plan.activePrice?.priceId;
    if (priceId == null) return null;
    return MemberMembershipsStartItem(
      memberId: memberId,
      priceId: priceId,
      quantity: quantity,
      discountIds: presetIds.toList(),
      customDiscounts: customs,
    );
  }

  @override
  List<Object?> get props => [plan, quantity, presetIds, customs];
}
