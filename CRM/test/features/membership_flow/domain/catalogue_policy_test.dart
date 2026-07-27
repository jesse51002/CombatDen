import 'package:flutter_test/flutter_test.dart';

import 'package:crm/features/member_details/data/models/membership_plan_price_response.dart';
import 'package:crm/features/member_details/data/models/membership_plan_response.dart';
import 'package:crm/features/member_details/data/models/plan_type.dart';
import 'package:crm/features/membership_flow/domain/catalogue_policy.dart';

/// **One catalogue, both surfaces.**
///
/// `is_public` used to mean "hide from the iPad, still sellable at the desk":
/// the kiosk filtered on it and the staff wizard did not, so a non-public plan
/// was a desk-only arrangement. That split is gone — a plan a member cannot see
/// is a plan staff cannot sell either, and there is no longer any UI that can
/// start one.
///
/// The reversal, if it is ever wanted, is one clause here: keep the filter
/// shared and make `isPublic` surface-scoped. It must never become two
/// independently-maintained filters again.
void main() {
  MembershipPlanResponse plan({
    required String planId,
    required bool isPublic,
    bool priced = true,
  }) =>
      MembershipPlanResponse(
        planId: planId,
        gymId: 'gym-1',
        planName: planId,
        imageUrl: 'https://cdn.example/$planId.png',
        planType: PlanType.recurring,
        isPublic: isPublic,
        createdAt: DateTime.utc(2026, 1, 1),
        activePrice: priced
            ? MembershipPlanPriceResponse(
                priceId: 'price-$planId',
                planId: planId,
                gymId: 'gym-1',
                stripePriceId: 'price_stripe_$planId',
                price: 10000,
                isActive: true,
                createdAt: DateTime.utc(2026, 1, 1),
              )
            : null,
      );

  test('a public, priced plan is sellable', () {
    expect(isSellablePlan(plan(planId: 'unlimited', isPublic: true)), isTrue);
  });

  test('a NON-public plan is sellable nowhere — including at the desk', () {
    expect(isSellablePlan(plan(planId: 'staff-comp', isPublic: false)),
        isFalse);
  });

  test('a plan with no active price has nothing to charge', () {
    // Both surfaces already refused this one; only the `isPublic` clause is
    // new. A price-less plan cannot produce a wire `price_id` at all.
    expect(
      isSellablePlan(plan(planId: 'draft', isPublic: true, priced: false)),
      isFalse,
    );
  });

  test('sellablePlans keeps catalogue order and drops the rest', () {
    final offered = sellablePlans([
      plan(planId: 'unlimited', isPublic: true),
      plan(planId: 'staff-comp', isPublic: false),
      plan(planId: 'draft', isPublic: true, priced: false),
      plan(planId: 'kids', isPublic: true),
    ]);

    expect(offered.map((p) => p.planId), ['unlimited', 'kids']);
  });

  test('an empty catalogue offers nothing rather than throwing', () {
    expect(sellablePlans(const []), isEmpty);
  });
}
