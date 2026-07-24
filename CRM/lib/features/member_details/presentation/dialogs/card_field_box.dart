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
///
/// [fieldKey] keys the inner [CardField]. On web the field is a Stripe iframe
/// whose platform view is CACHED across mounts, so a caller that must guarantee
/// a fresh, empty field on re-entry (the kiosk signup, after a decline) passes a
/// key that changes per attempt — without it the same iframe, still holding the
/// declined number, is reused and cannot be cleared.
class CardFieldBox extends StatelessWidget {
  final ValueChanged<bool> onComplete;

  /// Identity for the inner Stripe [CardField]. Change it to force a brand-new,
  /// empty field. Null keeps the default single cached field (every non-kiosk
  /// caller).
  final Key? fieldKey;

  const CardFieldBox({super.key, required this.onComplete, this.fieldKey});

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
          key: fieldKey,
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
