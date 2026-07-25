import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_cubit.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_buttons.dart';

/// "Start over?" — the confirmation an escape shows on the steps where real
/// work would die (the card step and the review steps). Every earlier step
/// abandons on the first tap.
///
/// **Composition = the shipped `KioskIdleWarning`, reused whole**: the same
/// ground-at-92% veil, the same popup card, the same accent-soft disc, the
/// same type. That is the point — the kiosk gets exactly ONE modal
/// vocabulary, so a member who has already seen the idle warning knows what
/// this surface is and that it is asking, not telling. The disc keeps the
/// accent-soft tint rather than the warm/warn treatment the front-desk stops
/// wear: this is a reversible question, not a dead end, and the palette must
/// not accuse.
///
/// **Button order and weight:** the SAFE choice is the primary and sits on the
/// right, where the primary sits on every other kiosk screen. Leaving is the
/// quiet outline on the left. A member panicking about a mis-tap should be
/// able to hit the biggest, bluest thing on the screen and have that be the
/// harmless answer.
///
/// **The 5-minute clock keeps running behind it.** If it expires while this is
/// up, the idle path wins and abandons — the member has demonstrably walked
/// away, and an unanswered dialog must never pin half-typed card details on a
/// lobby iPad indefinitely.
class KioskAbandonConfirm extends StatelessWidget {
  const KioskAbandonConfirm({super.key});

  @override
  Widget build(BuildContext context) {
    // An opaque gesture detector so a tap on the veil is ABSORBED here and
    // never leaks through to the step behind it. Unlike the idle warning, a
    // veil tap does not answer the question: this dialog asks something, and
    // a stray tap must not answer it either way.
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {},
        child: ColoredBox(
          color: DesignConstants.backgroundColor.withValues(alpha: 0.92),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: DesignConstants.dialogMaxWidth,
              ),
              // The card's containment from the screen edge — a Padding, not a
              // `margin`: a margin is a gap, and a gap belongs to the parent's
              // `spacing:`. It is the idle warning's inset, like the rest of
              // this surface.
              child: Padding(
                padding: const EdgeInsets.all(DesignConstants.paddingBig),
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
                      const _RestartIcon(),
                      Text(
                        'Start over?',
                        style: DesignConstants.kioskPanelTitle,
                        textAlign: TextAlign.center,
                      ),
                      Text(
                        'This clears everything you\'ve filled in, including '
                        'your card. Nothing has been charged.',
                        style: DesignConstants.kioskBody.copyWith(
                          color: DesignConstants.text2nd,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const _Answers(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Answers extends StatelessWidget {
  const _Answers();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingLarge,
      children: [
        KioskOutlineButton(
          text: 'Yes, start over',
          onPressed: () => context.read<KioskSignupCubit>().abandon(),
        ),
        KioskPrimaryButton(
          text: 'Keep going',
          onPressed: () => context.read<KioskSignupCubit>().dismissAbandon(),
        ),
      ],
    );
  }
}

/// The idle warning's disc, wearing the restart glyph the escape carries.
class _RestartIcon extends StatelessWidget {
  const _RestartIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(DesignConstants.paddingSmall),
      decoration: BoxDecoration(
        color: DesignConstants.accentSoft,
        shape: BoxShape.circle,
      ),
      child: Icon(
        Symbols.restart_alt_sharp,
        size: DesignConstants.iconSizeBig,
        weight: DesignConstants.iconWeight,
        color: DesignConstants.primaryColor,
      ),
    );
  }
}
