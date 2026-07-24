import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_state.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_buttons.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_card_chip.dart';

/// D8 — the card was refused, as a POPUP acknowledgement over the flow.
///
/// **Its natural action returns to the CARD-NUMBER page.** A decline is a
/// wrong card, not a wrong signup, so the primary is a single clear "Try
/// another card" that drops the member back on the card step with a fresh,
/// empty, working field (see `retryCard`). "Get help at the desk" is the
/// always-available SECONDARY handoff, never the forced destination — it
/// `_stop`s to `cardDeclined`, holding every committed row for the staff
/// incomplete-signups list.
///
/// **The copy blames the bank, never the member.** "Your bank declined the
/// payment" is true and blameless; "your card was rejected" reads as a verdict
/// on the person standing in a lobby. The reassurance is warm and UNCOUNTED —
/// a tally beside a refusal reads as a countdown to being cut off, which is not
/// what happens here.
///
/// **The velocity cooldown lives HERE, big.** After a run of declines the wait
/// is the popup's obvious focus — a large central countdown that gates
/// try-again until it reaches zero — rather than a small number hiding on a
/// background Pay button. The member row, Stripe customer and signatures are
/// all committed and never re-run; the session flow count is deliberately still
/// held, because the member is standing right there.
class KioskDeclinedScreen extends StatelessWidget {
  const KioskDeclinedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<KioskSignupCubit>();
    return BlocBuilder<KioskSignupCubit, KioskSignupState>(
      buildWhen: (prev, cur) =>
          prev.cardBrand != cur.cardBrand ||
          prev.cardLast4 != cur.cardLast4 ||
          prev.retryCooldown != cur.retryCooldown,
      builder: (context, state) {
        final cooling = state.retryCooldown > 0;
        return SizedBox.expand(
          child: ColoredBox(
            color: DesignConstants.backgroundColor.withValues(alpha: 0.92),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: DesignConstants.dialogMaxWidth,
                ),
                child: Container(
                  // A tighter margin than the other kiosk modals: this popup
                  // carries more (reason + chip + a big timer + two stacked
                  // buttons), so it needs the extra vertical room to sit whole
                  // on a short kiosk fold.
                  margin: const EdgeInsets.all(DesignConstants.spacingLarge),
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
                      if (cooling) _Cooldown(seconds: state.retryCooldown),
                      _Actions(
                        onRetry: cooling ? null : cubit.retryCard,
                        onHelp: cubit.getHelpAtDesk,
                      ),
                    ],
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

/// The velocity wait, made the popup's focus. A member cycling cards on an
/// unattended iPad hits it immediately; a real person fixing a typo essentially
/// never sees it. Try-again is gated until it elapses, so the number is the
/// answer to "why can't I press it".
class _Cooldown extends StatelessWidget {
  final int seconds;

  const _Cooldown({required this.seconds});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: DesignConstants.paddingSmall,
        vertical: DesignConstants.spacingLarge,
      ),
      decoration: BoxDecoration(
        color: DesignConstants.accentSoft,
        borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: DesignConstants.spacingSmall,
        children: [
          Text(
            'You can try again in',
            style: DesignConstants.kioskSubtitle.copyWith(
              color: DesignConstants.text2nd,
            ),
            textAlign: TextAlign.center,
          ),
          Text(
            '${seconds}s',
            style: DesignConstants.kioskDisplay.copyWith(
              color: DesignConstants.primaryColor,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// Try another card (the primary, gated while cooling), then the always-open
/// desk handoff below it — stacked because two kiosk-scale labels do not fit
/// side by side in a [DesignConstants.dialogMaxWidth] popup.
class _Actions extends StatelessWidget {
  final VoidCallback? onRetry;
  final VoidCallback onHelp;

  const _Actions({required this.onRetry, required this.onHelp});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingMedium,
      children: [
        KioskPrimaryButton(text: 'Try another card', onPressed: onRetry),
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
