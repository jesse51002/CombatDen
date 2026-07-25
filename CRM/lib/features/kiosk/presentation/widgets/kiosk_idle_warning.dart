import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/kiosk/bloc/kiosk_flow_cubit.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_buttons.dart';

/// The flow-idle warning — a veil over the in-progress flow with a visible
/// countdown. Any interaction dismisses it and resets the clock; on expiry the
/// cubit abandons the draft and returns home. Shown only DURING a flow, never
/// on the idle home.
///
/// One warning surface, two lanes: the check-in lane's guard lives on
/// [KioskFlowCubit], the signup lane runs its own. [onStillHere] routes "I'm
/// still here" to whichever clock is actually running — without it the button
/// answers a timer that isn't ticking and the member is ejected anyway.
class KioskIdleWarning extends StatelessWidget {
  final int seconds;

  /// Answers the countdown. Defaults to [KioskFlowCubit.registerActivity].
  final VoidCallback? onStillHere;

  const KioskIdleWarning({
    super.key,
    required this.seconds,
    this.onStillHere,
  });

  @override
  Widget build(BuildContext context) {
    void stillHere() {
      final answer = onStillHere;
      if (answer != null) {
        answer();
      } else {
        context.read<KioskFlowCubit>().registerActivity();
      }
    }

    return Positioned.fill(
      child: GestureDetector(
        // Opaque so a veil tap is absorbed here and can't leak through to a
        // class card behind it and trigger a check-in.
        behavior: HitTestBehavior.opaque,
        onTap: stillHere,
        child: ColoredBox(
          color: DesignConstants.backgroundColor.withValues(alpha: 0.92),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: DesignConstants.dialogMaxWidth,
              ),
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
                      const _TimerIcon(),
                      Text(
                        'Are you still there?',
                        style: DesignConstants.kioskPanelTitle,
                        textAlign: TextAlign.center,
                      ),
                      Text(
                        'Returning to the start in $seconds seconds.',
                        style: DesignConstants.kioskBody.copyWith(
                          color: DesignConstants.text2nd,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      KioskPrimaryButton(
                        text: 'I\'m still here',
                        onPressed: stillHere,
                      ),
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

class _TimerIcon extends StatelessWidget {
  const _TimerIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(DesignConstants.paddingSmall),
      decoration: BoxDecoration(
        color: DesignConstants.accentSoft,
        shape: BoxShape.circle,
      ),
      child: Icon(
        Symbols.timer_sharp,
        size: DesignConstants.iconSizeBig,
        weight: DesignConstants.iconWeight,
        color: DesignConstants.primaryColor,
      ),
    );
  }
}
