import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/kiosk/bloc/kiosk_flow_cubit.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_buttons.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_return_timer.dart';
import 'package:crm/shared/widgets/hairline.dart';

/// The glance's system footer: a hairline, the
/// "Back to start in Ns" auto-return countdown over a draining track, and a
/// visible Done button that returns home early. A tap anywhere else on the
/// glance opens the "Get the app" modal (wired at the glance surface); Done is
/// the explicit go-home affordance. The countdown [secondsLeft] is driven by
/// the cubit's 10-second hold, which only starts once the reveal's last beat
/// has landed — so the foot shows its full value (and a full drain bar) while
/// the glance is still assembling itself. Done works throughout, including
/// while the confirmation is still centred.
class KioskGlanceFoot extends StatelessWidget {
  final int secondsLeft;

  const KioskGlanceFoot({super.key, required this.secondsLeft});

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
            total: kKioskGlanceHold.inSeconds,
            secondsLeft: secondsLeft,
          ),
        ),
        Center(
          child: KioskOutlineButton(
            text: 'Done',
            onPressed: () => context.read<KioskFlowCubit>().goHome(),
          ),
        ),
      ],
    );
  }
}
