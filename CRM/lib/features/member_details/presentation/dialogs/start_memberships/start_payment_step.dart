import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/utils/money.dart';
import 'package:crm/features/member_details/data/models/card_on_file.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_preview.dart';
import 'package:crm/features/member_details/data/models/proration_behavior.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/custom_card_capture.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/one_time_card_section.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/saved_card_section.dart';

/// Step 7 — settlement. The saved card on file ([SavedCardSection],
/// editable) vs the REAL cash toggle (`paid_with_cash`: the one-time
/// invoice settles out-of-band, the recurring first invoice is marked
/// paid out-of-band, future cycles still auto-charge the card). When the
/// cart is purely one-time / trial the [OneTimeCardSection] lets staff
/// pay it with a one-off card entered now. Echoes the preview totals —
/// the last thing seen before PAY is the number.
class StartPaymentStep extends StatelessWidget {
  final CardOnFile? cardOnFile;
  final bool paidWithCash;
  final ValueChanged<bool> onPaidWithCashChanged;
  final bool hasRecurring;
  final bool hasOneTime;
  final CustomCardCapture? customCard;
  final VoidCallback onAddOrChangeCustomCard;
  final VoidCallback onRemoveCustomCard;
  final MemberMembershipsStartPreview? preview;

  /// The chosen proration (set on the preview step). The echoed
  /// preview was fetched at `prorate_to_anchor`, so the due-now row
  /// is shown only when that is the choice — `no_charge` bills
  /// nothing now.
  final ProrationBehavior prorationBehavior;
  final VoidCallback onAddNewCard;

  const StartPaymentStep({
    super.key,
    required this.cardOnFile,
    required this.paidWithCash,
    required this.onPaidWithCashChanged,
    required this.hasRecurring,
    required this.hasOneTime,
    required this.customCard,
    required this.onAddOrChangeCustomCard,
    required this.onRemoveCustomCard,
    required this.preview,
    required this.prorationBehavior,
    required this.onAddNewCard,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingLarge,
      children: [
        Text('How is this paid?',
            style: DesignConstants.h2),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: DesignConstants.spacingMedium,
          children: [
            SwitchListTile(
              value: paidWithCash,
              onChanged: onPaidWithCashChanged,
              activeThumbColor:
                  DesignConstants.primaryColor,
              contentPadding: EdgeInsets.zero,
              title: Text(
                'Paid in cash (no card charge today)',
                style: DesignConstants.p,
              ),
              subtitle: Text(
                'Today’s charges are settled in cash. '
                'Future recurring cycles auto-charge the '
                'card on file UNLESS you mark each '
                'invoice paid in cash first — so a '
                'cash-only subscription is fully '
                'supported, no card required.',
                style: DesignConstants.pSmall.copyWith(
                  color: DesignConstants.text2nd,
                ),
              ),
            ),
            if (!paidWithCash)
              SavedCardSection(
                cardOnFile: cardOnFile,
                hasRecurring: hasRecurring,
                onAddOrEdit: onAddNewCard,
              ),
            // A one-off card is offered ONLY for a purely one-time cart
            // (no recurring) — recurring always bills the saved card, so a
            // mixed cart never shows the option.
            if (!paidWithCash && hasOneTime && !hasRecurring)
              OneTimeCardSection(
                customCard: customCard,
                onAddOrChange: onAddOrChangeCustomCard,
                onRemove: onRemoveCustomCard,
              ),
            _TotalsEcho(
              preview: preview,
              prorationBehavior: prorationBehavior,
            ),
          ],
        ),
      ],
    );
  }
}

/// The preview totals, restated right above PAY.
class _TotalsEcho extends StatelessWidget {
  final MemberMembershipsStartPreview? preview;
  final ProrationBehavior prorationBehavior;

  const _TotalsEcho({
    required this.preview,
    required this.prorationBehavior,
  });

  @override
  Widget build(BuildContext context) {
    final p = preview;
    if (p == null || p.isEmpty) {
      return Text(
        'Loading the totals… if this persists, go back '
        'to the preview step to reload them.',
        style: DesignConstants.pSmall.copyWith(
          color: DesignConstants.text2nd,
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(
        DesignConstants.paddingSmall,
      ),
      decoration: BoxDecoration(
        color: DesignConstants.backgroundColor,
        borderRadius: BorderRadius.circular(
          DesignConstants.radiusBig,
        ),
        border:
            Border.all(color: DesignConstants.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingSmall,
        children: [
          if (p.oneTime != null)
            _TotalRow(
              label: 'One-time purchases (today)',
              amount: p.oneTime!.total,
              currency: p.oneTime!.currency,
            ),
          // due_now only applies when prorating; `no_charge` bills
          // nothing now (the preview was fetched at prorate_to_anchor).
          if (prorationBehavior == ProrationBehavior.prorateToAnchor &&
              p.dueNow != null)
            _TotalRow(
              label: 'Recurring — due now',
              amount: p.dueNow!.total,
              currency: p.dueNow!.currency,
            ),
          if (p.recurring != null)
            _TotalRow(
              label: 'Then, each cycle',
              amount: p.recurring!.total,
              currency: p.recurring!.currency,
              suffix: '/cycle',
            ),
        ],
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  final String label;
  final int amount;
  final String currency;
  final String? suffix;

  const _TotalRow({
    required this.label,
    required this.amount,
    required this.currency,
    this.suffix,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      spacing: DesignConstants.spacingMedium,
      children: [
        Expanded(
          child: Text(
            label,
            style: DesignConstants.p.copyWith(
              color: DesignConstants.text2nd,
            ),
          ),
        ),
        Text(
          '${formatMinorUnits(amount, currency: currency)}'
          '${suffix ?? ''}',
          style: DesignConstants.h3,
        ),
      ],
    );
  }
}
