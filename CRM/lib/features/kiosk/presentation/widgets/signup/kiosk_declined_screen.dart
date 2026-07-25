import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_state.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_buttons.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_return_timer.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_card_chip.dart';

/// D8 — the card was refused, as a popup acknowledgement over the flow.
///
/// Only an ALL-FAILED start reaches this popup, which is exactly why "you
/// haven't been charged" is true here. The account is not untouched, though:
/// the start attaches the fresh card and promotes it to the payer's Stripe
/// default before it charges, and a decline reverts neither (founder ruling) —
/// so the copy states that card fact rather than implying nothing changed.
///
/// No cooldown and no attempt limit (founder ruling). Retry is live from the
/// first frame and re-attempts the SAME card (`retrySameCard`) because the
/// common decline is insufficient funds; velocity throttling rides on the
/// platform Stripe Radar rule, never a client-side wait or strike count. "Try
/// another card" (`retryCard`) re-keys the field for a different one, and "Get
/// help at the desk" holds every committed row for the staff
/// incomplete-signups list. The 60-second countdown is not a cooldown — it
/// decides how long a shared iPad may sit here unanswered before the ordinary
/// abandon runs.
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
                // needs the extra room to sit whole on a short kiosk fold.
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
                          'You haven\'t been charged, and nothing you filled '
                          'in is lost. The card you entered is now the one '
                          'saved on your profile.',
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

/// Retry the same card first, then a different card, then the always-open desk
/// handoff — stacked because three kiosk-scale labels do not fit side by side
/// in a [DesignConstants.dialogMaxWidth] popup.
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
/// card. Warm, not red: nobody did anything wrong.
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
