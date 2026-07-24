import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/state/selected_gym.dart';
import 'package:crm/features/kiosk/bloc/kiosk_flow_cubit.dart';
import 'package:crm/features/kiosk/presentation/kiosk_app_copy.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_app_line.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_buttons.dart';
import 'package:crm/shared/widgets/hairline.dart';

/// The app-adoption strip that closes the QR half of the kiosk home: a hairline
/// rule, then the white-labelled adoption line and its "Get it" button on ONE
/// row.
///
/// **One row, not a stack.** The home is two columns and only this one carries
/// a foot, so every line the foot spends is weight the search half has nothing
/// to answer with — the columns are co-centred by
/// `kiosk_home_columns.dart` and the left half still read heavier than the
/// right (founder). Sitting the sentence and its button side by side halves the
/// foot's height and turns two loose objects into a single adopt strip: the
/// line says what and where, the button is the verb.
///
/// **The button keeps its `compact` primary treatment** — filled because it is
/// the one adopt action, at the secondary rung's metrics so it doesn't
/// out-shout the "New here? Sign up" button below the columns. It is not a
/// third size; see [KioskPrimaryButton].
///
/// **The row degrades by narrowing the SENTENCE, never the button.** The line
/// is the only [Flexible] child, so a long gym name ("Get the Northside
/// Brazilian Jiu-Jitsu Academy app in the App Store.") wraps inside the row
/// while the button holds its width and its place beside it — it can never be
/// pushed out of the column or off the fold. Two lines is the floor the line
/// then ellipsizes at, so no gym name can tower the strip back up to the height
/// this layout exists to remove.
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
        Row(
          // Centred as a GROUP: the pair reads as one object on the column's
          // centre line, the same line the head and the QR above it sit on.
          mainAxisAlignment: MainAxisAlignment.center,
          spacing: DesignConstants.spacingLarge,
          children: [
            Flexible(
              // White-labelled: the member downloads THEIR GYM's app — see
              // `kiosk_app_copy.dart`. `selectedGym` is the same source the
              // kiosk header names the gym from.
              child: KioskAppLine(
                text: kioskAppStoreLine(selectedGym.gymName),
                maxLines: 2,
              ),
            ),
            KioskPrimaryButton(
              text: 'Get it',
              compact: true,
              onPressed: () => context.read<KioskFlowCubit>().openAppModal(),
            ),
          ],
        ),
      ],
    );
  }
}
