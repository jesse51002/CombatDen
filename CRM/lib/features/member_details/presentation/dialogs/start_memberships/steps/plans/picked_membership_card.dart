import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_cubit.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_draft.dart';
import 'package:crm/features/member_details/data/models/plan_type.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/steps/plans/picked_membership_head.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/wizard_copy.dart';
import 'package:crm/features/membership_flow/config/cart_policy.dart';
import 'package:crm/features/membership_flow/config/membership_flow_theme.dart';
import 'package:crm/features/membership_flow/discounts/discounts_capability.dart';
import 'package:crm/features/membership_flow/discounts/flow_discount_section.dart';
import 'package:crm/features/membership_flow/presentation/widgets/flow_quantity_stepper.dart';

/// ONE picked membership, as the card that sells it.
///
/// The kiosk's picked banner grown up: it owns this membership's pack count,
/// its live price and — the point of the whole redesign — its OWN discounts.
/// Discounts attach per MEMBERSHIP and never per member, which is what the
/// backend has always modelled, so two picked plans mean two of these cards
/// and the separate discounts step disappears with them.
class PickedMembershipCard extends StatelessWidget {
  final MembershipWizardCubit cubit;
  final DiscountsCapability discounts;
  final CartPolicy cart;
  final MembershipWizardDraft draft;

  /// Which of this person's picks this is, and how many there are.
  final int index;
  final int total;

  final String memberId;
  final String firstName;

  const PickedMembershipCard({
    super.key,
    required this.cubit,
    required this.discounts,
    required this.cart,
    required this.draft,
    required this.index,
    required this.total,
    required this.memberId,
    required this.firstName,
  });

  @override
  Widget build(BuildContext context) {
    final planId = draft.plan.planId;
    return Container(
      padding: const EdgeInsets.all(DesignConstants.paddingSmall),
      decoration: BoxDecoration(
        color: DesignConstants.primaryColor10,
        borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: DesignConstants.spacingMedium,
        children: [
          PickedMembershipHead(
            discounts: discounts,
            draft: draft,
            index: index,
            total: total,
            firstName: firstName,
            onRemove: () => cubit.removeMembership(memberId, planId),
          ),
          if (_offersQuantity) _Packs(cubit: cubit, draft: draft, cart: cart),
          FlowDiscountSection(
            discounts: discounts,
            presetIds: draft.presetIds,
            customs: draft.customs,
            onAddPreset: (id) => cubit.togglePresetDiscount(planId, id),
            onAddCustom: (value) => cubit.addCustomDiscount(planId, value),
            onRemove: (reference) => _remove(planId, reference),
          ),
        ],
      ),
    );
  }

  /// A recurring membership is pinned to one unit by a database trigger, so
  /// the control is ABSENT there rather than disabled — the same rule the
  /// whole config follows.
  bool get _offersQuantity =>
      cart.offersQuantity && draft.plan.planType != PlanType.recurring;

  void _remove(String planId, FlowDiscountReference reference) {
    switch (reference) {
      case FlowPresetDiscount(:final presetId):
        cubit.togglePresetDiscount(planId, presetId);
      case FlowCustomDiscount(:final index):
        cubit.removeCustomDiscount(planId, index);
    }
  }
}

/// How many packs this line stacks. The allowance and the price both follow
/// the count, and the note beside the stepper says so.
class _Packs extends StatelessWidget {
  final MembershipWizardCubit cubit;
  final MembershipWizardDraft draft;
  final CartPolicy cart;

  const _Packs({
    required this.cubit,
    required this.draft,
    required this.cart,
  });

  @override
  Widget build(BuildContext context) {
    final scale = MembershipFlowTheme.of(context);
    return Row(
      spacing: DesignConstants.spacingMedium,
      children: [
        FlowQuantityStepper(
          units: draft.quantity,
          cart: cart,
          label: WizardPlansCopy.packsLabel,
          decrementSemanticLabel: WizardPlansCopy.fewerPacks,
          incrementSemanticLabel: WizardPlansCopy.morePacks,
          onChanged: (units) => cubit.setQuantity(draft.plan.planId, units),
        ),
        Expanded(
          child: Text(
            WizardPlansCopy.packsNote,
            style: scale.caption.copyWith(color: DesignConstants.text2nd),
          ),
        ),
      ],
    );
  }
}
