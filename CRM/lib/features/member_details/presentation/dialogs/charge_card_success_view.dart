import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/utils/money.dart';

/// The charge dialog's success step: a green-check confirmation
/// built entirely from what staff entered (amount, how it settled,
/// the reason) — the charge endpoint returns no body to render.
/// [paidCash] flips the copy to the out-of-band (cash) wording;
/// otherwise [cardLabel] names the card billed. [payerName] is shown
/// only when there was a payer choice (a linked family).
class ChargeCardSuccessView extends StatelessWidget {
  final int amountCents;
  final bool paidCash;

  /// The card billed — non-null when [paidCash] is false.
  final String? cardLabel;
  final String reason;
  final String? payerName;

  const ChargeCardSuccessView({
    super.key,
    required this.amountCents,
    required this.reason,
    this.paidCash = false,
    this.cardLabel,
    this.payerName,
  });

  @override
  Widget build(BuildContext context) {
    final amount = formatMinorUnits(amountCents, decimalDigits: 2);
    final payer = payerName;
    final title = paidCash ? 'Payment recorded' : 'Card charged';
    final detail = paidCash
        ? '$amount recorded as paid in cash for "$reason".'
        : '$amount charged to $cardLabel for "$reason".';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingLarge,
      children: [
        Icon(
          Symbols.check_circle_sharp,
          weight: DesignConstants.iconWeight,
          size: DesignConstants.iconSizeBig,
          color: DesignConstants.goodGreen,
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          spacing: DesignConstants.spacingSmall,
          children: [
            Text(title, style: DesignConstants.h2),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: DesignConstants.p.copyWith(
                color: DesignConstants.text2nd,
              ),
            ),
            if (payer != null)
              Text(
                'Paid by $payer',
                textAlign: TextAlign.center,
                style: DesignConstants.pSmall.copyWith(
                  color: DesignConstants.text2nd,
                ),
              ),
          ],
        ),
      ],
    );
  }
}
