import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_state.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_buttons.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_return_timer.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_card_chip.dart';

/// D8 — the card was refused, as a POPUP acknowledgement over the flow.
///
/// **Three stacked actions, Retry first.** The most common decline is
/// insufficient funds, so the primary is a single clear "Retry" that re-attempts
/// the SAME card the member already entered (see `retrySameCard`) — a member who
/// just moved money doesn't re-type their card. Below it, "Try another card"
/// (secondary) drops them back on the card step with a fresh, empty, working
/// field (see `retryCard`) for a genuinely different card. "Get help at the
/// desk" is the always-available handoff at the bottom — it `_stop`s to
/// `cardDeclined`, holding every committed row for the staff incomplete-signups
/// list.
///
/// **There is no cooldown and no attempt limit.** Retry is live from the first
/// frame and a member may use it as many times as they like — attempt-velocity
/// throttling rides entirely on the platform Stripe Radar rule (a founder
/// decision), never a client-side wait or strike count. The member row, Stripe
/// customer and signatures are all committed and are never re-run.
///
/// **It does carry a 60-second RETURN countdown, inside the popup.** That is a
/// different thing from a cooldown: it decides how long a shared community
/// iPad may sit on this screen with nobody answering it, not how soon Retry may
/// be tapped. Expiry runs the ordinary abandon, which is what finally releases
/// the session flow count this step deliberately holds while the member is
/// still standing there.
///
/// **The copy blames the bank, never the member.** "Your bank declined the
/// payment" is true and blameless; "your card was rejected" reads as a verdict
/// on the person standing in a lobby. The reassurance is warm and UNCOUNTED —
/// a tally beside a refusal reads as a countdown to being cut off, which is not
/// what happens here.
class KioskDeclinedScreen extends StatelessWidget {
  const KioskDeclinedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<KioskSignupCubit>();
    return BlocBuilder<KioskSignupCubit, KioskSignupState>(
      buildWhen: (prev, cur) =>
          prev.cardBrand != cur.cardBrand ||
          prev.cardLast4 != cur.cardLast4 ||
          prev.popupCountdown != cur.popupCountdown,
      builder: (context, state) {
        return SizedBox.expand(
          child: ColoredBox(
            color: DesignConstants.backgroundColor.withValues(alpha: 0.92),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: DesignConstants.dialogMaxWidth,
                ),
                // A tighter inset than the other kiosk modals: this popup
                // carries more (reason + chip + three stacked buttons), so it
                // needs the extra vertical room to sit whole on a short kiosk
                // fold. It is the card's containment from the screen edge — a
                // Padding, never a `margin`: a margin is a gap, and a gap
                // belongs to the parent's `spacing:`.
                child: Padding(
                  padding: const EdgeInsets.all(DesignConstants.spacingLarge),
                  child: Container(
                    padding: const EdgeInsets.all(DesignConstants.paddingBig),
                    decoration: BoxDecoration(
                      color: DesignConstants.popup,
                      borderRadius:
                          BorderRadius.circular(DesignConstants.radiusCard),
                      border: Border.all(color: DesignConstants.line),
                      boxShadow: DesignConstants.cardShadow,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      spacing: DesignConstants.spacingLarge,
                      children: [
                        const _DeclinedIcon(),
                        Text(
                          'Your bank declined the payment',
                          style: DesignConstants.kioskPanelTitle,
                          textAlign: TextAlign.center,
                        ),
                        Text(
                          'You haven\'t been charged, and everything else you '
                          'filled in is saved.',
                          style: DesignConstants.kioskBody.copyWith(
                            color: DesignConstants.text2nd,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        KioskCardChip(
                          brand: state.cardBrand,
                          last4: state.cardLast4,
                        ),
                        _Actions(
                          onRetry: cubit.retrySameCard,
                          onTryAnother: cubit.retryCard,
                          onHelp: cubit.getHelpAtDesk,
                        ),
                        KioskReturnTimer(
                          total: kKioskSignupPopupHold.inSeconds,
                          secondsLeft: state.popupCountdown,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Retry the same card (the primary — the common insufficient-funds case),
/// then "Try another card" for a different one, then the always-open desk
/// handoff below both — stacked because three kiosk-scale labels do not fit
/// side by side in a [DesignConstants.dialogMaxWidth] popup.
class _Actions extends StatelessWidget {
  final VoidCallback onRetry;
  final VoidCallback onTryAnother;
  final VoidCallback onHelp;

  const _Actions({
    required this.onRetry,
    required this.onTryAnother,
    required this.onHelp,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingMedium,
      children: [
        KioskPrimaryButton(text: 'Retry', onPressed: onRetry),
        KioskOutlineButton(text: 'Try another card', onPressed: onTryAnother),
        KioskOutlineButton(text: 'Get help at the desk', onPressed: onHelp),
      ],
    );
  }
}

/// The warm disc the kiosk's other handoffs wear, carrying a struck-through
/// card. Warm, not red: nothing here is broken and nobody did anything wrong.
class _DeclinedIcon extends StatelessWidget {
  const _DeclinedIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(DesignConstants.paddingSmall),
      decoration: BoxDecoration(
        color: DesignConstants.yellowDark,
        shape: BoxShape.circle,
      ),
      child: Icon(
        Symbols.credit_card_off_sharp,
        size: DesignConstants.iconSizeBig,
        weight: DesignConstants.iconWeight,
        color: DesignConstants.okYellow,
      ),
    );
  }
}
