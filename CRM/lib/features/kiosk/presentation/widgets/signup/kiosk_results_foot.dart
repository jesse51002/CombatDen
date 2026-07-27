import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_cubit.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_return_timer.dart';
import 'package:crm/shared/widgets/hairline.dart';

/// The results receipt's footer: a hairline, the return countdown, then the
/// screen's decisions — the shape every kiosk TERMINAL wears.
///
/// Deliberately NOT `FlowFoot`, which carries the ghost escape in its left
/// gutter by construction: money has moved by the time this screen renders, so
/// there is nothing to start over. The escape pattern belongs to steps that can
/// be corrected or abandoned, never to a terminal.
///
/// The actions stack rather than sitting side by side — three kiosk-scale
/// labels do not fit across a `dialogMaxWidth` measure.
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
        // The decline popup's action column, so a receipt's buttons are the
        // same objects at the same size.
        Column(
          mainAxisSize: MainAxisSize.min,
          spacing: DesignConstants.spacingMedium,
          children: actions,
        ),
      ],
    );
  }
}
