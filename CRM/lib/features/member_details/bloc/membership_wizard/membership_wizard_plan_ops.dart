import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_base.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_consequence.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_derived.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_draft.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_load.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_plans.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_roster.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_step.dart';
import 'package:crm/features/member_details/data/models/discount_value.dart';
import 'package:crm/features/member_details/data/models/membership_plan_response.dart';

/// The plans step's controls — one person's lineup, and the discounts attached
/// INLINE to each membership on it.
///
/// There is no discounts STEP: a price reduction is a property of the
/// membership being sold, so it is configured on the card that sells it. That
/// is what takes the flow from `6 + 2N` screens to `5 + N`.
mixin MembershipWizardPlanOps on MembershipWizardBase {
  /// Pick or un-pick [plan] for the person whose plans step is open.
  ///
  /// A plan a GATE closes is never picked — the desk carries one gate, the
  /// backend's own duplicate-recurring guard, which staff cannot talk their
  /// way past either, so a blocked pick could only fail at the money step.
  void togglePlan(MembershipPlanResponse plan) {
    final memberId = state.currentPerson?.memberId;
    if (memberId == null) return;
    final held = state
        .draftsFor(memberId)
        .any((draft) => draft.plan.planId == plan.planId);
    if (!held && state.gateFor(memberId, plan) != null) return;
    _setLineup(
      memberId,
      draftsWithPlanToggled(
        drafts: state.draftsFor(memberId),
        plan: plan,
        cart: state.config.cart,
      ),
    );
  }

  /// Set one membership's pack count. The value is brought inside the desk's
  /// own cart policy and pinned to 1 for a recurring plan.
  void setQuantity(String planId, int quantity) {
    final memberId = state.currentPerson?.memberId;
    if (memberId == null) return;
    _setLineup(
      memberId,
      draftsWithQuantity(
        drafts: state.draftsFor(memberId),
        planId: planId,
        quantity: quantity,
        cart: state.config.cart,
      ),
    );
  }

  /// Toggle one of the gym's preset discounts on a membership.
  void togglePresetDiscount(String planId, String presetId) {
    final memberId = state.currentPerson?.memberId;
    if (memberId == null) return;
    _setLineup(
      memberId,
      draftsWithPresetToggled(
        drafts: state.draftsFor(memberId),
        planId: planId,
        presetId: presetId,
      ),
    );
  }

  /// Attach a one-off custom discount to a membership — minted server-side as
  /// a single-use `custom` row when the start commits.
  void addCustomDiscount(String planId, DiscountValue value) {
    final memberId = state.currentPerson?.memberId;
    if (memberId == null) return;
    _setLineup(
      memberId,
      draftsWithCustomAdded(
        drafts: state.draftsFor(memberId),
        planId: planId,
        value: value,
      ),
    );
  }

  /// Take one custom back off a membership.
  void removeCustomDiscount(String planId, int index) {
    final memberId = state.currentPerson?.memberId;
    if (memberId == null) return;
    _setLineup(
      memberId,
      draftsWithCustomRemoved(
        drafts: state.draftsFor(memberId),
        planId: planId,
        index: index,
      ),
    );
  }

  /// What removing one membership from the review would cost — itself, and the
  /// person when it was their last.
  MembershipWizardConsequence? consequenceOfRemoving(
    String memberId,
    String planId,
  ) {
    for (final person in state.people) {
      if (person.memberId != memberId) continue;
      return removeMembershipConsequence(
        person: person,
        planId: planId,
        drafts: state.drafts,
      );
    }
    return null;
  }

  /// Remove one membership from the review. When it was that person's last,
  /// they stop being part of the run — and the consequence says so, rather than
  /// the row simply vanishing along with them.
  void removeMembership(String memberId, String planId) {
    final consequence = consequenceOfRemoving(memberId, planId);
    if (consequence == null || !consequence.destroys) return;
    final remaining = draftsWithMembershipRemoved(state.drafts, memberId, planId);
    final losesPerson = !remaining.containsKey(memberId);
    emit(
      state.copyWith(
        drafts: remaining,
        trainingMemberIds: losesPerson
            ? {
                for (final id in state.trainingMemberIds)
                  if (id != memberId) id,
              }
            : state.trainingMemberIds,
        preview: null,
        previewRequest: null,
        previewLoad: const MembershipWizardLoad.idle(),
        lastConsequence: consequence,
      ),
    );
    emit(state.copyWith(personIndex: clampPersonIndex(state.personIndex)));
  }

  /// Edit one person's lineup FROM the review: jump to their plans step, and
  /// come straight back to the review when it is finished.
  void editFromReview(String memberId) {
    final at = state.trainingPeople
        .indexWhere((person) => person.memberId == memberId);
    if (at < 0) return;
    emit(
      state.copyWith(
        step: MembershipWizardStep.plans,
        personIndex: at,
        editReturnsToReview: true,
      ),
    );
  }

  /// Write one person's lineup back, clearing any staged preview: a cart that
  /// changed is a price that changed, and a stale figure beside a live cart is
  /// how a payer is quoted one number and charged another.
  void _setLineup(String memberId, List<MembershipWizardDraft> lineup) {
    emit(
      state.copyWith(
        drafts: lineup.isEmpty
            ? draftsWithout(state.drafts, memberId)
            : {...state.drafts, memberId: lineup},
        preview: null,
        previewRequest: null,
        previewLoad: const MembershipWizardLoad.idle(),
      ),
    );
  }
}
