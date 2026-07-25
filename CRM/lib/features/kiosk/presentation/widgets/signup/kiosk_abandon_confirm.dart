import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_cubit.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_buttons.dart';

/// "Start over?" — the confirmation the escape shows on the steps where real
/// work would die (card and review); every earlier step abandons on the first
/// tap.
///
/// It reuses `KioskIdleWarning` whole, so the kiosk keeps exactly ONE modal
/// vocabulary, and keeps that modal's accent-soft disc rather than the warm
/// treatment the front-desk stops wear: this is a reversible question, not a
/// dead end, and the palette must not accuse.
///
/// The SAFE answer is the primary, on the right. A member panicking about a
/// mis-tap must be able to hit the biggest, bluest thing on the screen and
/// have that be the harmless one.
class KioskAbandonConfirm extends StatelessWidget {
  const KioskAbandonConfirm({super.key});

  @override
  Widget build(BuildContext context) {
    // Opaque so a veil tap is ABSORBED, never leaking to the step behind and
    // — unlike the idle warning — never answering the question either way.
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
              // The idle warning's inset, like the rest of this surface.
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
