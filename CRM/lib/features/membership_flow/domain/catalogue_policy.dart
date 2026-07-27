/// The ONE filter deciding which of a gym's plans a membership-purchase
/// surface may offer.
///
/// A plan with no active price has nothing to charge, and a non-public plan is
/// not part of the gym's offer. Both surfaces apply the same filter, so a plan
/// that can be sold at the desk is exactly the plan that can be sold on the
/// iPad — there is no third state where a catalogue row is buyable in one
/// place and invisible in the other.
library;

import 'package:crm/features/member_details/data/models/membership_plan_response.dart';

/// Whether [plan] may be offered on a purchase surface.
bool isSellablePlan(MembershipPlanResponse plan) =>
    plan.isPublic && plan.activePrice != null;

/// [all], narrowed to the plans a purchase surface may offer, in order.
List<MembershipPlanResponse> sellablePlans(
  Iterable<MembershipPlanResponse> all,
) =>
    all.where(isSellablePlan).toList();
