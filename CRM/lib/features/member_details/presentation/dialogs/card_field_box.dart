import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

import 'package:crm/core/constants/design_constants.dart';

/// The app's bordered Stripe [CardField] box, shared by every
/// card-entry dialog (update-card, one-off checkout card).
/// Card details go straight to Stripe and never reach our
/// servers; this widget only reports completeness via
/// [onComplete] — tokenization stays with the caller.
///
/// All colours are theme tokens so the Stripe field follows
/// light/dark mode. The field's background is transparent, so
/// it shows this box's [DesignConstants.card]; the typed text
/// ([style]), the placeholders ([InputDecoration.hintStyle] →
/// Stripe `::placeholder`) and the cursor must all be set, or
/// the unset placeholder falls back to Stripe's dark default
/// and reads as black-on-black in dark mode.
class CardFieldBox extends StatelessWidget {
  final ValueChanged<bool> onComplete;

  const CardFieldBox({super.key, required this.onComplete});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: DesignConstants.card,
        borderRadius: BorderRadius.circular(
          DesignConstants.radiusBig,
        ),
        border: Border.all(
          color: DesignConstants.text,
          width: 2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: DesignConstants.spacingMedium,
        ),
        child: CardField(
          enablePostalCode: true,
          style: DesignConstants.p.copyWith(
            color: DesignConstants.text,
          ),
          cursorColor: DesignConstants.text,
          decoration: InputDecoration(
            border: InputBorder.none,
            hintStyle: DesignConstants.p.copyWith(
              color: DesignConstants.text2nd,
            ),
          ),
          onCardChanged: (details) =>
              onComplete(details?.complete ?? false),
        ),
      ),
    );
  }
}
