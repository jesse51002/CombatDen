import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_derived.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_state.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/steps/shared/wizard_money_line.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/steps/shared/wizard_recurring_lines.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/wizard_copy.dart';
import 'package:crm/features/membership_flow/presentation/chrome/flow_detail_group.dart';
import 'package:crm/features/membership_flow/presentation/widgets/flow_two_charges_note.dart';
import 'package:crm/shared/widgets/hairline.dart';

/// What PAY will do, echoed once more directly above the button that does it.
///
/// The same three figures the review just showed, in the same order, from the
/// same reads — this is the last screen before a real card is charged, and
/// scrolling back to check a number is exactly what nobody does at a busy
/// front desk.
class WizardPaymentTotalsGroup extends StatelessWidget {
  final MembershipWizardState state;

  /// The last four of the card that will actually settle today. Null on a cash
  /// run, and on a run with no card at all.
  final String? cardLast4;

  const WizardPaymentTotalsGroup({
    super.key,
    required this.state,
    required this.cardLast4,
  });

  @override
  Widget build(BuildContext context) {
    final existing = state.payerDetail?.totalMonthlyRecurringPrice ?? 0;
    final added = wizardRecurringAddedMinor(state);
    return FlowDetailGroup(
      eyebrow: WizardPaymentCopy.whatPayWillDoEyebrow,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          spacing: DesignConstants.spacingMedium,
          children: [
            WizardMoneyLine(
              label: WizardPaymentCopy.dueTodayOn(cardLast4),
              amountMinorUnits: state.dueTodayMinor,
              currency: state.currency,
            ),
            if (added > 0)
              WizardMoneyLine(
                label: WizardPaymentCopy.addedEachCycle,
                amountMinorUnits: added,
                currency: state.currency,
              ),
            if (existing > 0)
              WizardMoneyLine(
                label: WizardReviewCopy.alreadyPaying(state.payer.firstName),
                amountMinorUnits: existing,
                currency: state.currency,
              ),
            if (added > 0 || existing > 0) ...[
              const Hairline(),
              WizardMoneyLine(
                label: WizardReviewCopy.monthlyTotal(state.payer.firstName),
                amountMinorUnits: added + existing,
                currency: state.currency,
                total: true,
              ),
            ],
          ],
        ),
        // Two charges is a fact about the payer's own statement, so it is read
        // here before the card is taken and again on the receipt after it
        // clears — the identical sentence in both places.
        if (state.chargedTwice) const FlowTwoChargesNote(),
      ],
    );
  }
}
