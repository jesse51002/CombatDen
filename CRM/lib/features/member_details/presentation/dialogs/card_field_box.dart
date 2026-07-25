import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/network/stripe_account_context.dart';

/// The app's bordered Stripe [CardField] box, shared by every
/// card-entry surface (update-card / one-off checkout card in the
/// member-detail dialogs, and the kiosk signup's card step).
/// Card details go straight to Stripe and never reach our servers;
/// this widget only reports completeness via [onComplete] —
/// tokenization stays with the caller.
///
/// **The field is gated on the gym's connected account.** The backend runs
/// direct-charge Stripe Connect, so a card must be tokenized on the gym's
/// connected account (a platform-owned `pm_…` cannot attach to a
/// connected-account customer). The connected account is applied to Stripe.js
/// by [stripeAccountContext] when the active gym is established; a Stripe
/// [CardField] binds to whichever JS Stripe object exists at MOUNT time, so
/// this box waits for [StripeAccountContext.isReady] before mounting the field
/// — that is what guarantees the account is applied first. When no connected
/// account is available (a gym that hasn't finished Stripe onboarding, or a
/// failed apply) it fails closed and never mounts a field, so the client can
/// never tokenize onto the platform account.
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
    // Rebuild when the connected-account context resolves / changes, so the
    // field mounts only once the account is applied.
    return ListenableBuilder(
      listenable: stripeAccountContext,
      builder: (context, _) {
        if (!stripeAccountContext.isReady) {
          // The account context hasn't resolved yet. In the running app it is
          // applied at login, long before any card surface opens, so this is a
          // momentary state — never mount a field against a stale JS Stripe
          // object.
          return const _CardFieldStatus(
            message: 'Preparing secure card entry…',
            showSpinner: true,
          );
        }
        if (!stripeAccountContext.paymentsAvailable) {
          // Fail closed: no connected account (gym not onboarded) or the Stripe
          // context failed to apply. Refuse card entry rather than tokenize
          // onto the platform account.
          return const _CardFieldStatus(
            message: 'Card entry is unavailable right now.',
            showSpinner: false,
          );
        }
        return _CardField(onComplete: onComplete, fieldKey: fieldKey);
      },
    );
  }
}

/// The live bordered Stripe field, mounted only once the connected account is
/// applied (see [CardFieldBox]).
class _CardField extends StatelessWidget {
  final ValueChanged<bool> onComplete;
  final Key? fieldKey;

  const _CardField({required this.onComplete, this.fieldKey});

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

/// The same-shaped bordered box shown in place of the field while the connected
/// account is still resolving, or when card entry is unavailable — so there is
/// no layout jump when the real field takes its place.
class _CardFieldStatus extends StatelessWidget {
  final String message;
  final bool showSpinner;

  const _CardFieldStatus({required this.message, required this.showSpinner});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: DesignConstants.card,
        borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
        border: Border.all(color: DesignConstants.line, width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: DesignConstants.spacingMedium,
          vertical: DesignConstants.spacingLarge,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          spacing: DesignConstants.spacingSmall,
          children: [
            if (showSpinner)
              SizedBox(
                width: DesignConstants.iconSizeSmall,
                height: DesignConstants.iconSizeSmall,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: DesignConstants.text2nd,
                ),
              ),
            Flexible(
              child: Text(
                message,
                style: DesignConstants.pSmall.copyWith(
                  color: DesignConstants.text2nd,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
