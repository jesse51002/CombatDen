import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/kiosk/bloc/kiosk_flow_cubit.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_buttons.dart';

/// The flow-idle warning — a veil over the in-progress flow with a visible
/// countdown. Any interaction anywhere dismisses it and resets the 5-minute
/// clock (the whole kiosk surface listens for pointer activity); on expiry the
/// cubit abandons the draft and returns home. Shown only while a flow is in
/// progress, never on the idle home screen.
class KioskIdleWarning extends StatelessWidget {
  final int seconds;

  const KioskIdleWarning({super.key, required this.seconds});

  @override
  Widget build(BuildContext context) {
    // An opaque gesture detector so a tap on the veil dismisses the warning
    // AND is absorbed here — it must never leak through to a class card behind
    // it and trigger a check-in.
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => context.read<KioskFlowCubit>().registerActivity(),
        child: ColoredBox(
          color: DesignConstants.backgroundColor.withValues(alpha: 0.92),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: DesignConstants.dialogMaxWidth,
              ),
              child: Container(
                margin: const EdgeInsets.all(DesignConstants.paddingBig),
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
                      onPressed: () =>
                          context.read<KioskFlowCubit>().registerActivity(),
                    ),
                  ],
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
