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

/// The app-adoption strip that closes the kiosk home: a hairline spanning the
/// whole stage, then the white-labelled adoption line and its "Get it" button
/// on ONE row beneath it.
///
/// **It spans BOTH columns and belongs to neither.** Getting the app is a
/// property of the whole screen — the member who scans and the member who types
/// their name both end up wanting it — so it was never a property of the QR
/// column. While it lived in that column's foot, only one half of the home had
/// a foot at all, which left that half structurally heavier however small the
/// strip got (founder). Spanning it empties both feet, so the two columns
/// balance by construction rather than by tuning one side down.
///
/// **It is the LAST band on the screen, below "Start Trial / Membership".** The
/// rule is the one categorical boundary on the home: above it is every way to
/// get in right now (scan, search, buy), below it is the one thing that is
/// about later. A person who is blocked at the kiosk — nothing to train on
/// yet — outranks a nudge nobody is waiting on, so that entry keeps the higher
/// slot and the adoption strip takes the terminal one.
///
/// **The rule spans; the pair does not.** The hairline runs the full width
/// because its job is to close everything above it. The line and the button are
/// centred as a GROUP inside [DesignConstants.kioskAdoptMeasure] — nothing in
/// the row pushes them apart (no `Expanded`, no `Spacer`), and the cap keeps
/// the sentence inside a readable measure instead of letting a long gym name
/// stretch it across an entire iPad.
///
/// **One row, not a stack.** Sitting the sentence and its button side by side
/// halves the strip's height and turns two loose objects into a single adopt
/// strip: the line says what and where, the button is the verb.
///
/// **The button keeps its `compact` primary treatment** — filled because it is
/// the one adopt action, at the secondary rung's metrics so it doesn't
/// out-shout the "Start Trial / Membership" button above it. It is not a third
/// size; see [KioskPrimaryButton].
///
/// **The row degrades by narrowing the SENTENCE, never the button.** The line
/// is the only [Flexible] child, so a long gym name ("Get the Northside
/// Brazilian Jiu-Jitsu Academy app in the App Store.") wraps inside the row
/// while the button holds its width and its place beside it. Two lines is the
/// floor the line then ellipsizes at, so no gym name can tower the strip back
/// up to the height this layout exists to remove.
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
          // it narrows, so any intrinsic-height parent has to measure it at the
          // cap rather than at the full span.
          child: MeasuredMaxWidth(
            maxWidth: DesignConstants.kioskAdoptMeasure,
            child: Row(
              // Centred as a GROUP: the pair reads as one object on the
              // screen's centre line, the same line the title and the seam sit
              // on — never a sentence and a button at opposite edges of a band
              // twice as wide as the column that used to hold them.
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
