import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_derived.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_draft.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_person.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_state.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/wizard_copy.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/wizard_views.dart';
import 'package:crm/features/membership_flow/config/membership_flow_theme.dart';
import 'package:crm/features/membership_flow/discounts/flow_discount_chip.dart';
import 'package:crm/features/membership_flow/domain/plan_labels.dart';
import 'package:crm/features/membership_flow/presentation/widgets/flow_buy_row.dart';
import 'package:crm/features/membership_flow/presentation/widgets/flow_row_action.dart';

/// One person's block on the review: who they are, what was picked for them,
/// and what came off each line.
///
/// Everybody the payer covers is listed, including a payer who is buying
/// nothing themselves — the run bills their card either way, and a name
/// missing from this list is a name staff cannot check.
class WizardReviewPersonBlock extends StatelessWidget {
  final MembershipWizardState state;
  final MembershipWizardPerson person;
  final ValueChanged<String> onEdit;
  final void Function(String memberId, String planId) onRemove;

  const WizardReviewPersonBlock({
    super.key,
    required this.state,
    required this.person,
    required this.onEdit,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final copy = MembershipFlowTheme.copyOf(context);
    final scale = MembershipFlowTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingMedium,
      children: [
        Row(
          spacing: DesignConstants.spacingMedium,
          children: [
            Flexible(
              child: Text(
                person.name,
                style: scale.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // A payer who is ALSO buying carries both eyebrows, and this half
            // of the review is the narrowest measure on the screen — so they
            // wrap rather than clip. They answer different questions ("whose
            // card is this" and "who is this run for"), so neither may be
            // dropped to make the row fit.
            Expanded(
              child: Wrap(
                spacing: DesignConstants.spacingMedium,
                runSpacing: DesignConstants.spacingSmall,
                children: [
                  if (person.isPayer)
                    Text(
                      copy.payingEyebrow,
                      style: scale.eyebrow.copyWith(
                        color: DesignConstants.primaryColor,
                      ),
                    ),
                  if (person.training)
                    Text(copy.memberEyebrow, style: scale.eyebrow),
                ],
              ),
            ),
            // Only somebody the run is buying FOR has a lineup to edit.
            if (person.training)
              FlowRowAction(
                semanticLabel: copy.editSemantic(person.name),
                icon: Symbols.edit_sharp,
                label: copy.editAction,
                onTap: () => onEdit(person.memberId),
              ),
          ],
        ),
        for (final draft in state.draftsFor(person.memberId))
          _Line(
            state: state,
            person: person,
            draft: draft,
            onRemove: onRemove,
          ),
      ],
    );
  }
}

/// One picked membership: the plan, its price (with what it was reduced FROM),
/// the trash that takes it off, and the discounts that explain the drop.
class _Line extends StatelessWidget {
  final MembershipWizardState state;
  final MembershipWizardPerson person;
  final MembershipWizardDraft draft;
  final void Function(String memberId, String planId) onRemove;

  const _Line({
    required this.state,
    required this.person,
    required this.draft,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final money = wizardLineMoney(state, draft);
    final labels = money == null
        ? null
        : wizardLineLabels(money, currency: state.currency);
    final applied = state.discounts.appliedFor(
      presetIds: draft.presetIds,
      customs: draft.customs,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingSmall,
      children: [
        Row(
          spacing: DesignConstants.spacingMedium,
          children: [
            Expanded(
              child: FlowBuyRow(
                name: draft.plan.planName,
                rule: WizardReviewCopy.lineRule(
                  planAllowanceLabel(draft.plan, count: draft.quantity),
                  draft.quantity,
                ),
                imageUrl: draft.plan.imageUrl,
                amount: labels?.amount,
                struckAmount: labels?.struck,
              ),
            ),
            FlowRowAction(
              // Already names the plan AND the person, which is what a reader
              // hearing four trash cans down a family lineup needs.
              semanticLabel: WizardPlansCopy.removeMembership(
                draft.plan.planName,
                person.firstName,
              ),
              icon: Symbols.delete_sharp,
              onTap: () => onRemove(person.memberId, draft.plan.planId),
            ),
          ],
        ),
        if (applied.isNotEmpty)
          Padding(
            // Indented onto the row's text rail, under the name the chips
            // explain — the thumb's own width plus the row's gap.
            padding: const EdgeInsets.only(
              left: DesignConstants.iconSizeBig +
                  DesignConstants.spacingLarge +
                  DesignConstants.spacingMedium,
            ),
            child: Wrap(
              spacing: DesignConstants.spacingSmall,
              runSpacing: DesignConstants.spacingSmall,
              children: [
                for (final discount in applied)
                  FlowDiscountChip(
                    label: discount.label,
                    // Read-only here: the review states what was applied, and
                    // the plans step is where it is changed. With no remove
                    // callback the semantic label is never rendered.
                    removeSemanticLabel: '',
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
