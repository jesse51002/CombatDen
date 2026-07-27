/// One person's lineup, and the discounts attached INLINE to each membership
/// on it.
///
/// Pure list surgery over [MembershipWizardDraft]s. The two rules worth having
/// here rather than in a widget are that a recurring membership's quantity is
/// pinned to 1 whatever a stepper says (`trg_recurring_quantity_must_be_one`
/// refuses anything else, and finding that out at the money step is the
/// failure this prevents), and that the desk's own [CartPolicy] is what caps a
/// pack — never a literal.
library;

import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_draft.dart';
import 'package:crm/features/member_details/data/models/discount_value.dart';
import 'package:crm/features/member_details/data/models/membership_plan_response.dart';
import 'package:crm/features/member_details/data/models/plan_type.dart';
import 'package:crm/features/membership_flow/config/cart_policy.dart';

/// [drafts] with [plan] picked or un-picked. Un-picking drops the membership's
/// discounts with it: a price reduction belongs to the membership, so a
/// re-pick starts clean rather than silently restoring a discount nobody
/// re-chose.
List<MembershipWizardDraft> draftsWithPlanToggled({
  required List<MembershipWizardDraft> drafts,
  required MembershipPlanResponse plan,
  required CartPolicy cart,
}) {
  final held = drafts.indexWhere((d) => d.plan.planId == plan.planId);
  if (held >= 0) {
    return [
      for (var i = 0; i < drafts.length; i++)
        if (i != held) drafts[i],
    ];
  }
  if (!cart.canPickAnotherPlan(drafts.length)) return drafts;
  return [...drafts, MembershipWizardDraft(plan: plan)];
}

/// [drafts] with one membership's pack count set, brought inside the surface's
/// own cart policy and pinned to 1 for a recurring plan.
List<MembershipWizardDraft> draftsWithQuantity({
  required List<MembershipWizardDraft> drafts,
  required String planId,
  required int quantity,
  required CartPolicy cart,
}) =>
    _mapDraft(
      drafts,
      planId,
      (draft) => draft.copyWith(
        quantity: draft.plan.planType == PlanType.recurring
            ? 1
            : cart.clampQuantity(quantity),
      ),
    );

/// [drafts] with one of the gym's preset discounts toggled on a membership.
List<MembershipWizardDraft> draftsWithPresetToggled({
  required List<MembershipWizardDraft> drafts,
  required String planId,
  required String presetId,
}) =>
    _mapDraft(drafts, planId, (draft) {
      final ids = Set<String>.from(draft.presetIds);
      if (!ids.remove(presetId)) ids.add(presetId);
      return draft.copyWith(presetIds: ids);
    });

/// [drafts] with a one-off custom appended to a membership. Appended, never
/// merged: two identical customs on one membership are two real discounts, and
/// collapsing them would quietly halve what was granted.
List<MembershipWizardDraft> draftsWithCustomAdded({
  required List<MembershipWizardDraft> drafts,
  required String planId,
  required DiscountValue value,
}) =>
    _mapDraft(
      drafts,
      planId,
      (draft) => draft.copyWith(customs: [...draft.customs, value]),
    );

/// [drafts] with the custom at [index] taken off a membership. An index the
/// list no longer holds is a no-op rather than a throw — a removal racing a
/// re-render must not take down the dialog.
List<MembershipWizardDraft> draftsWithCustomRemoved({
  required List<MembershipWizardDraft> drafts,
  required String planId,
  required int index,
}) =>
    _mapDraft(drafts, planId, (draft) {
      if (index < 0 || index >= draft.customs.length) return draft;
      return draft.copyWith(
        customs: [
          for (var i = 0; i < draft.customs.length; i++)
            if (i != index) draft.customs[i],
        ],
      );
    });

List<MembershipWizardDraft> _mapDraft(
  List<MembershipWizardDraft> drafts,
  String planId,
  MembershipWizardDraft Function(MembershipWizardDraft) change,
) =>
    [
      for (final draft in drafts)
        if (draft.plan.planId == planId) change(draft) else draft,
    ];
