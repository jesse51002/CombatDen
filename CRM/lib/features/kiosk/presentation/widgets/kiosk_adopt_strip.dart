import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/state/selected_gym.dart';
import 'package:crm/features/kiosk/bloc/kiosk_flow_cubit.dart';
import 'package:crm/features/kiosk/presentation/kiosk_app_copy.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_app_line.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_buttons.dart';
import 'package:crm/shared/widgets/hairline.dart';
import 'package:crm/shared/widgets/measured_max_width.dart';

/// The app-adoption strip that closes the kiosk home: a hairline, then the
/// white-labelled adoption line and its "Get it" button on one row.
///
/// Spans BOTH columns and is the LAST band on the screen — getting the app is
/// about later, so it sits below every way to get in right now. The line is
/// the only [Flexible] child, so a long gym name wraps rather than squeezing
/// the button. The button stays `compact` (primary tier at the secondary
/// rung's metrics) so it doesn't out-shout "Start Trial / Membership" above
/// it — see [KioskPrimaryButton].
class KioskAdoptStrip extends StatelessWidget {
  const KioskAdoptStrip({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingLarge,
      children: [
        const Hairline(),
        Center(
          // MeasuredMaxWidth, not ConstrainedBox: the sentence grows TALLER as
          // it narrows, so it must be measured at the cap, not the full span.
          child: MeasuredMaxWidth(
            maxWidth: DesignConstants.kioskAdoptMeasure,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              spacing: DesignConstants.spacingLarge,
              children: [
                Flexible(
                  // White-labelled: the member downloads THEIR GYM's app —
                  // see `kiosk_app_copy.dart`.
                  child: KioskAppLine(
                    text: kioskAppStoreLine(selectedGym.gymName),
                    maxLines: 2,
                  ),
                ),
                KioskPrimaryButton(
                  text: 'Get it',
                  compact: true,
                  onPressed: () =>
                      context.read<KioskFlowCubit>().openAppModal(),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
