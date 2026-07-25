import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_cubit.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_return_timer.dart';
import 'package:crm/shared/widgets/hairline.dart';

/// The results receipt's footer: a hairline, the return countdown, then the
/// screen's decisions — `KioskWelcomeScreen._Foot`'s shape, which is the shape
/// every kiosk TERMINAL wears.
///
/// **It is deliberately NOT `KioskFlowFoot`.** That foot carries the ghost
/// escape in its left gutter by construction, and money has moved by the time
/// this screen renders — there is nothing to start over. This is
/// `KioskSignupStopScreen`'s stated rule ("the escape pattern appears where a
/// step can be corrected or abandoned — never on a terminal") and the welcome
/// screen follows it too. `KioskStage` takes any widget in its `footer` slot, so
/// no scaffold change is needed to use this instead.
///
/// The actions stack rather than sitting side by side, matching the decline
/// popup: three kiosk-scale labels do not fit across a `dialogMaxWidth` measure,
/// and the all-created branch's single Next reads the same either way.
class KioskResultsFoot extends StatelessWidget {
  /// Seconds left on the 60-second return countdown.
  final int secondsLeft;

  /// The screen's decisions, loudest first. One Next on the all-created branch;
  /// the decline ladder (Retry / another card / the desk) on a partial.
  final List<Widget> actions;

  const KioskResultsFoot({
    super.key,
    required this.secondsLeft,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingMedium,
      children: [
        const Hairline(),
        Center(
          child: KioskReturnTimer(
            total: kKioskSignupPopupHold.inSeconds,
            secondsLeft: secondsLeft,
          ),
        ),
        // Intrinsic widths, centred — the decline popup's own action column, so
        // a receipt's buttons are the same objects at the same size.
        Column(
          mainAxisSize: MainAxisSize.min,
          spacing: DesignConstants.spacingMedium,
          children: actions,
        ),
      ],
    );
  }
}
