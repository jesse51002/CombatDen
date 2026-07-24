import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_state.dart';
import 'package:crm/features/kiosk/presentation/kiosk_signup_stop_copy.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_buttons.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_return_timer.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_stage.dart';

/// The signup's terminal front-desk handoff — the composition
/// `KioskBlockedScreen` already ships (icon, one display line, a WHY box, the
/// reassurance, one acknowledged action), plus the auto-return countdown a
/// signup stop needs because it can be reached with nobody left standing
/// there.
///
/// **There is deliberately NO escape affordance.** A dead end already IS the
/// exit: "Okay, got it" returns home, so a gutter "Start over" would be a
/// second button doing the identical thing and would only make the member
/// wonder which one is different. The escape pattern appears where a step can
/// be corrected or abandoned — never on a terminal.
///
/// Both exits (the button and the countdown) release the session's flow count
/// exactly once — the cubit's `abandon()` runs the same latch either way.
class KioskSignupStopScreen extends StatelessWidget {
  const KioskSignupStopScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<KioskSignupCubit, KioskSignupState>(
      buildWhen: (prev, cur) =>
          prev.stopReason != cur.stopReason ||
          prev.stopCountdown != cur.stopCountdown,
      builder: (context, state) {
        return KioskStage(
          center: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: DesignConstants.spacingLarge,
            children: [
              const _StopIcon(),
              Text(
                'Let\'s finish this at the front desk',
                style: DesignConstants.kioskDisplay,
                textAlign: TextAlign.center,
              ),
              _WhyBox(reason: kioskSignupStopReasonCopy(state.stopReason)),
              Text(
                kioskSignupStopReassurance(state.stopReason),
                style: DesignConstants.kioskSubtitle.copyWith(
                  color: DesignConstants.text2nd,
                ),
                textAlign: TextAlign.center,
              ),
              _Actions(reason: state.stopReason),
              KioskReturnTimer(
                total: kKioskSignupStopHold.inSeconds,
                secondsLeft: state.stopCountdown,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The stop's action row.
///
/// A dead end gets ONE button, because the dead end already IS the exit. The
/// two **retryable** reasons — a plan catalogue that wouldn't load, a total we
/// couldn't work out — get a "Try again" primary in front of it, because a
/// failed read is not a dead end and telling a member to fetch a coach for one
/// is wrong. A money path never appears here: retrying a charge whose outcome
/// is unknown is the one action that could take the money twice.
class _Actions extends StatelessWidget {
  final KioskSignupStopReason? reason;

  const _Actions({required this.reason});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<KioskSignupCubit>();
    final retryable = reason?.isRetryable ?? false;
    if (!retryable) {
      return KioskPrimaryButton(
        text: 'Okay, got it',
        onPressed: cubit.abandon,
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingLarge,
      children: [
        KioskOutlineButton(text: 'Okay, got it', onPressed: cubit.abandon),
        KioskPrimaryButton(text: 'Try again', onPressed: cubit.stopRetry),
      ],
    );
  }
}

/// The blocked screen's warm disc, wearing the person glyph the duplicate
/// stop draws — this stop is about WHO the member is, not about a class.
class _StopIcon extends StatelessWidget {
  const _StopIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(DesignConstants.paddingSmall),
      decoration: BoxDecoration(
        color: DesignConstants.yellowDark,
        borderRadius: BorderRadius.circular(DesignConstants.radiusCard),
      ),
      child: Icon(
        Symbols.person_sharp,
        size: DesignConstants.iconSizeBig,
        weight: DesignConstants.iconWeight,
        color: DesignConstants.okYellow,
      ),
    );
  }
}

/// The one-line reason, boxed and eyebrowed — `KioskBlockedScreen`'s `_WhyBox`
/// composition, verbatim.
class _WhyBox extends StatelessWidget {
  final String reason;

  const _WhyBox({required this.reason});

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
          Text(reason, style: DesignConstants.kioskStatement),
        ],
      ),
    );
  }
}
