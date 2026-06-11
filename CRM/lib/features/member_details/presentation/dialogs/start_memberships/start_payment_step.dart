import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/utils/money.dart';
import 'package:crm/features/member_details/data/models/card_on_file.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_preview.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/card_wallet_section.dart';

/// Step 7 — settlement. Card on file (the wallet UI is a
/// known placeholder — see [CardWalletSection]) vs the REAL
/// cash toggle (`paid_with_cash`: the one-time invoice
/// settles out-of-band, the recurring first invoice is
/// marked paid out-of-band, future cycles still auto-charge
/// the card). Echoes the preview totals — the last thing
/// seen before PAY is the number.
class StartPaymentStep extends StatelessWidget {
  final CardOnFile? cardOnFile;
  final bool paidWithCash;
  final ValueChanged<bool> onPaidWithCashChanged;
  final bool prorate;
  final ValueChanged<bool> onProrateChanged;
  final bool hasRecurring;
  final MemberMembershipsStartPreview? preview;
  final VoidCallback onAddNewCard;

  const StartPaymentStep({
    super.key,
    required this.cardOnFile,
    required this.paidWithCash,
    required this.onPaidWithCashChanged,
    required this.prorate,
    required this.onProrateChanged,
    required this.hasRecurring,
    required this.preview,
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
                'Today’s charges are recorded as '
                'settled in cash; future recurring '
                'cycles still charge the card.',
                style: DesignConstants.pSmall.copyWith(
                  color: DesignConstants.text2nd,
                ),
              ),
            ),
            if (!paidWithCash)
              CardWalletSection(
                cardOnFile: cardOnFile,
                onAddNew: onAddNewCard,
              ),
            if (hasRecurring)
              SwitchListTile(
                value: prorate,
                onChanged: onProrateChanged,
                activeThumbColor:
                    DesignConstants.primaryColor,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Prorate the first recurring charge',
                  style: DesignConstants.p,
                ),
                subtitle: Text(
                  'Charge only for the remainder of '
                  'the current cycle.',
                  style: DesignConstants.pSmall.copyWith(
                    color: DesignConstants.text2nd,
                  ),
                ),
              ),
            _TotalsEcho(preview: preview),
          ],
        ),
      ],
    );
  }
}

/// The preview totals, restated right above PAY.
class _TotalsEcho extends StatelessWidget {
  final MemberMembershipsStartPreview? preview;

  const _TotalsEcho({required this.preview});

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
          if (p.dueNow != null)
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
