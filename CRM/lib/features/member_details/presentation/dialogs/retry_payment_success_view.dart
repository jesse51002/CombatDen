import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/utils/money.dart';

/// The retry-payment dialog's success step: a green-check confirmation
/// that [payerName]'s card on file covered the overdue invoice. Built
/// from the amount the invoice card already showed — the endpoint
/// returns no body (mirrors `charge_card_success_view.dart`).
class RetryPaymentSuccessView extends StatelessWidget {
  final int amountCents;
  final String currency;
  final String payerName;

  const RetryPaymentSuccessView({
    super.key,
    required this.amountCents,
    required this.currency,
    required this.payerName,
  });

  @override
  Widget build(BuildContext context) {
    final amount = formatMinorUnits(amountCents, currency: currency);
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
            Text('Payment collected', style: DesignConstants.h2),
            Text(
              '$amount was charged to $payerName’s card on file. '
              'The invoice is settled.',
              textAlign: TextAlign.center,
              style: DesignConstants.p.copyWith(
                color: DesignConstants.text2nd,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
