import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/utils/money.dart';
import 'package:crm/shared/widgets/error_message.dart';

/// The retry-payment dialog's confirm step: what the retry does, what it
/// charges, and the out — Update Card — when the saved card is the thing
/// that is dead. Doubles as the terminal error surface: a decline lands
/// back here with the backend's [error] above a still-live Retry button.
class RetryPaymentConfirmView extends StatelessWidget {
  final int amount;
  final String currency;
  final String payerName;
  final String? error;

  const RetryPaymentConfirmView({
    super.key,
    required this.amount,
    required this.currency,
    required this.payerName,
    this.error,
  });

  @override
  Widget build(BuildContext context) {
    final money = formatMinorUnits(amount, currency: currency);
    final message = error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingLarge,
      children: [
        Text(
          'Charge $payerName’s card on file $money for the unpaid '
          'invoice? This re-runs the card that is already saved — '
          'no new card is collected here.',
          style: DesignConstants.p.copyWith(
            color: DesignConstants.text,
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: DesignConstants.spacingSmall,
          children: [
            _EffectRow(
              icon: Symbols.credit_card_sharp,
              text: '$money charged to the card already on file.',
            ),
            const _EffectRow(
              icon: Symbols.autorenew_sharp,
              text: 'Worth a try when the failure was temporary — a '
                  'hold, a daily limit, a one-off bank decline.',
            ),
            const _EffectRow(
              icon: Symbols.credit_card_off_sharp,
              text: 'If the card is expired or cancelled this will '
                  'fail again — use Update Card first.',
            ),
          ],
        ),
        if (message != null) ErrorMessage(message: message),
      ],
    );
  }
}

/// One bulleted effect line. Mirrors the shared billing-confirmation
/// dialog's effect row; inlined here because this flow owns its own
/// processing → terminal steps and so cannot use that dialog's
/// pop-on-confirm shell.
class _EffectRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _EffectRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingSmall,
      children: [
        Icon(
          icon,
          size: DesignConstants.iconSizeMedium,
          weight: DesignConstants.iconWeight,
          color: DesignConstants.primaryColor,
        ),
        Expanded(
          child: Text(
            text,
            style: DesignConstants.p.copyWith(
              color: DesignConstants.text,
            ),
          ),
        ),
      ],
    );
  }
}
