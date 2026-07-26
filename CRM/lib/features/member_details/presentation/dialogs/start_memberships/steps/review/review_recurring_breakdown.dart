import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_derived.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_state.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/steps/shared/wizard_money_line.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/steps/shared/wizard_recurring_lines.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/wizard_copy.dart';
import 'package:crm/features/membership_flow/config/membership_flow_theme.dart';
import 'package:crm/shared/widgets/hairline.dart';

/// What the payer's recurring bill is MADE of once this run lands: the
/// memberships it adds, the ones they already pay for, and the sum.
///
/// Two figures that must never be mistaken for one another. The panel's own
/// headline above states what this run ADDS — that is the number being sold.
/// This states what the card is left paying every cycle, which is the number
/// the payer will actually see, and it names the memberships already on it so
/// the jump is never a surprise.
///
/// The total is the sum of the lines PRINTED here: a breakdown whose parts do
/// not add up to its own total is the fastest way to make staff distrust every
/// number on the screen.
class WizardReviewRecurringBreakdown extends StatelessWidget {
  final MembershipWizardState state;

  const WizardReviewRecurringBreakdown({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final scale = MembershipFlowTheme.of(context);
    final lines = wizardRecurringLines(state);
    final existing = state.payerDetail?.totalMonthlyRecurringPrice ?? 0;
    final added = wizardRecurringAddedMinor(state);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingMedium,
      children: [
        Text(
          WizardReviewCopy.addedByRun,
          style: scale.caption.copyWith(color: DesignConstants.text2nd),
        ),
        for (final line in lines)
          WizardMoneyLine(
            label: line.label,
            amountMinorUnits: line.amount,
            currency: state.currency,
          ),
        if (existing > 0)
          WizardMoneyLine(
            label: WizardReviewCopy.alreadyPaying(state.payer.firstName),
            amountMinorUnits: existing,
            currency: state.currency,
          ),
        const Hairline(),
        WizardMoneyLine(
          label: WizardReviewCopy.monthlyTotal(state.payer.firstName),
          amountMinorUnits: added + (existing > 0 ? existing : 0),
          currency: state.currency,
          total: true,
        ),
      ],
    );
  }
}
