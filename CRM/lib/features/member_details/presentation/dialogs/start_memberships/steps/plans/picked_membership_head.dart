import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_draft.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/wizard_copy.dart';
import 'package:crm/features/membership_flow/config/membership_flow_theme.dart';
import 'package:crm/features/membership_flow/discounts/discounts_capability.dart';
import 'package:crm/features/membership_flow/discounts/flow_discounted_price.dart';
import 'package:crm/features/membership_flow/domain/plan_labels.dart';
import 'package:crm/features/membership_flow/presentation/widgets/flow_row_action.dart';

/// The top row of a picked-membership card: which pick it is, what it is,
/// what it costs right now, and the one control that takes it back off.
///
/// Kiosk rule knowingly broken — its picked banner never names a price. Staff
/// sell on price, so the card shows the live one, with the estimate line under
/// the grid saying which figure is the authoritative one.
class PickedMembershipHead extends StatelessWidget {
  final DiscountsCapability discounts;
  final MembershipWizardDraft draft;
  final int index;
  final int total;
  final String firstName;
  final VoidCallback onRemove;

  const PickedMembershipHead({
    super.key,
    required this.discounts,
    required this.draft,
    required this.index,
    required this.total,
    required this.firstName,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final unit = draft.plan.activePrice?.price;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingMedium,
      children: [
        const _TickDisc(),
        Expanded(child: _Identity(draft: draft, index: index, total: total)),
        if (unit != null)
          FlowDiscountedPrice(
            discounts: discounts,
            unitPriceCents: unit,
            units: draft.quantity,
            presetIds: draft.presetIds,
            customs: draft.customs,
            cadence: planPriceSuffix(draft.plan),
          ),
        FlowRowAction(
          semanticLabel: WizardPlansCopy.removeMembership(
            draft.plan.planName,
            firstName,
          ),
          icon: Symbols.delete_sharp,
          onTap: onRemove,
        ),
      ],
    );
  }
}

/// Which pick this is, then what it is and what it gets you.
class _Identity extends StatelessWidget {
  final MembershipWizardDraft draft;
  final int index;
  final int total;

  const _Identity({
    required this.draft,
    required this.index,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    final scale = MembershipFlowTheme.of(context);
    final copy = MembershipFlowTheme.copyOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingTiny,
      children: [
        Text(
          copy.pickedEyebrow(index: index, total: total),
          style: scale.eyebrow.copyWith(color: DesignConstants.primaryColor),
        ),
        Text(
          draft.plan.planName,
          style: scale.statement,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          planAllowanceLabel(draft.plan, count: draft.quantity),
          style: scale.caption.copyWith(color: DesignConstants.text2nd),
        ),
      ],
    );
  }
}

/// The sapphire tick disc — the plan card's selected mark, at card scale.
class _TickDisc extends StatelessWidget {
  const _TickDisc();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: DesignConstants.iconSizeBig,
      height: DesignConstants.iconSizeBig,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: DesignConstants.primaryColor,
        shape: BoxShape.circle,
      ),
      child: Icon(
        Symbols.check_sharp,
        size: DesignConstants.iconSizeSmall,
        weight: DesignConstants.iconWeight,
        color: DesignConstants.onAccent,
      ),
    );
  }
}
