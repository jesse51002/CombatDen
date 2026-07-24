import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_state.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_buttons.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_stage.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_card_chip.dart';

/// D8 — the card was refused. Retries the CHARGE, and only the charge.
///
/// **The copy blames the bank, never the member.** "Your bank declined the
/// payment" is true and blameless; "your card was rejected" reads as a verdict
/// on the person standing in a lobby.
///
/// **Exactly two buttons, and neither of them is "Start over".** By this point
/// the member row, the Stripe customer and every signature are committed and
/// nothing rolls them back, so an abandon here would drop a half-built account
/// at a clean home screen with nobody told. Giving up is a HANDOFF, not an
/// abandon. The session's flow count is deliberately still held: the member is
/// standing right there.
///
/// **Neither button is ever forced.** A refused card is retryable for as long
/// as the member wants to keep trying — mistakes are ordinary and no count of
/// them ends a signup — so "Try another card" is always there and "Get help at
/// the desk" is the option beside it, never the destination. What repetition
/// buys is a short wait before the next attempt; the review's Pay button shows
/// it counting down.
class KioskDeclinedScreen extends StatelessWidget {
  const KioskDeclinedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<KioskSignupCubit>();
    return BlocBuilder<KioskSignupCubit, KioskSignupState>(
      buildWhen: (prev, cur) =>
          prev.declineCount != cur.declineCount ||
          prev.cardLast4 != cur.cardLast4,
      builder: (context, state) {
        return KioskStage(
          center: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: DesignConstants.spacingLarge,
            children: [
              const _DeclinedIcon(),
              Text(
                'That card didn\'t go through',
                style: DesignConstants.kioskDisplay,
                textAlign: TextAlign.center,
              ),
              const _WhyBox(),
              KioskCardChip(brand: state.cardBrand, last4: state.cardLast4),
              Text(
                _reassurance(state.declineCount),
                style: DesignConstants.kioskSubtitle.copyWith(
                  color: DesignConstants.text2nd,
                ),
                textAlign: TextAlign.center,
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                spacing: DesignConstants.spacingLarge,
                children: [
                  KioskOutlineButton(
                    text: 'Get help at the desk',
                    onPressed: cubit.getHelpAtDesk,
                  ),
                  KioskPrimaryButton(
                    text: 'Try another card',
                    onPressed: cubit.retryCard,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  /// The reassurance, warm and UNCOUNTED. A repeat gets a slightly gentler
  /// line rather than a tally: a member who has tried twice knows they have
  /// tried twice, and printing the number only ever reads as a countdown to
  /// being cut off — which is not something that happens here.
  String _reassurance(int declines) {
    const base = 'You haven\'t been charged, and everything else you filled '
        'in is saved. ';
    return declines > 1
        ? '${base}Another card usually does it — take your time, or the desk '
            'can help.'
        : '${base}A different card usually works — or the desk can take it '
            'from here.';
  }
}

/// The one-line reason, boxed and eyebrowed — `KioskBlockedScreen`'s `_WhyBox`
/// composition, verbatim. The reason is fixed here because a decline reason is
/// the bank's, not ours: Stripe's own decline codes are guesses about someone
/// else's decision and are no use to a member in a lobby.
class _WhyBox extends StatelessWidget {
  const _WhyBox();

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(
        maxWidth: DesignConstants.dialogMaxWidth,
      ),
      padding: const EdgeInsets.all(DesignConstants.paddingSmall),
      decoration: BoxDecoration(
        color: DesignConstants.surface,
        borderRadius: BorderRadius.circular(DesignConstants.radiusCard),
        border: Border.all(color: DesignConstants.line),
        boxShadow: DesignConstants.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        spacing: DesignConstants.spacingSmall,
        children: [
          Text('WHY', style: DesignConstants.kioskEyebrow),
          Text(
            'Your bank declined the payment.',
            style: DesignConstants.kioskStatement,
          ),
        ],
      ),
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
        borderRadius: BorderRadius.circular(DesignConstants.radiusCard),
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
