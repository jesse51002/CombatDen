import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/kiosk/bloc/kiosk_flow_cubit.dart';
import 'package:crm/features/kiosk/presentation/widgets/get_app/kiosk_app_card.dart';
import 'package:crm/features/kiosk/presentation/widgets/get_app/kiosk_app_showcase.dart';
import 'package:crm/features/kiosk/presentation/widgets/get_app/kiosk_showcase_slide.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_buttons.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_get_app_modal.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_return_timer.dart';
import 'package:crm/shared/widgets/hairline.dart';

/// Everything INSIDE the "Get the app" popup surface: the two nested cards
/// side by side, over the popup's own timer + Done foot.
///
/// **One popup, two nested cards, and the foot lives inside it too** (founder
/// ruling). The panels used to float straight on the veil with the foot
/// dangling under them, which read as three loose objects rather than one thing
/// that had opened. `KioskGetAppModal` supplies the single solid surface; this
/// widget only lays out its contents.
///
/// **It never scrolls, by construction.** A kiosk member does not discover
/// content below a fold, so the composition is *fitted* to the viewport rather
/// than allowed to grow past it: the foot is laid out first and the two cards
/// take an [Expanded] share of what is left, which bounds their height; inside
/// each card a `ShrinkToFit` turns a fold too short for the content into one
/// uniform scale-down of that whole card — the ramp, the artwork and the
/// spacing keeping their proportions — instead of an overflow. Never add a
/// scroll view here; a scrollbar on a kiosk is content nobody will ever see.
class KioskGetAppBody extends StatelessWidget {
  final String gymId;

  /// The gym's own name — the app card is white-labelled after it.
  final String? gymName;

  final int secondsLeft;
  final String? memberEmail;
  final List<KioskShowcaseSlide> slides;

  const KioskGetAppBody({
    super.key,
    required this.gymId,
    required this.gymName,
    required this.secondsLeft,
    required this.memberEmail,
    required this.slides,
  });

  @override
  Widget build(BuildContext context) {
    final card = KioskAppCard(
      gymName: gymName,
      downloadUrl: kioskAppDownloadUrl(gymId),
      memberEmail: memberEmail,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingLarge,
      children: [
        // THE fit guarantee: the cards take whatever height is left after the
        // foot, never more. Because that box is bounded, each card's content
        // is bounded too, and `ShrinkToFit` inside them turns a short fold
        // into a proportional scale-down instead of an overflow or a scroll.
        Expanded(
          child: slides.isEmpty
              // A gym with nothing to show yet (no classes loaded, no rewards,
              // no feed, no ranks): the app card carries the popup alone
              // rather than an empty second card or a stand-in slide. Capped
              // so it doesn't stretch across the full popup measure.
              ? Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: DesignConstants.dialogMaxWidth,
                    ),
                    child: card,
                  ),
                )
              // Two equal halves, like the glance's two panels — both stretched
              // to the same bounded height, so neither can push the popup
              // past the fold.
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: DesignConstants.spacingLarge,
                  children: [
                    Expanded(child: card),
                    Expanded(child: KioskAppShowcase(slides: slides)),
                  ],
                ),
        ),
        _Foot(secondsLeft: secondsLeft),
      ],
    );
  }
}

/// The popup's own footer, INSIDE the surface: a hairline, the 60-second
/// auto-close countdown, and Done.
///
/// Done closes the overlay and hands the member back to whatever was underneath
/// it — the glance they were reading, or the home they opened it from — while
/// the countdown running out means nobody is standing there, which returns
/// home. That split lives in [KioskFlowCubit.closeAppModal]; this button only
/// asks for it.
class _Foot extends StatelessWidget {
  final int secondsLeft;

  const _Foot({required this.secondsLeft});

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
            total: kKioskAppModalTimeout.inSeconds,
            secondsLeft: secondsLeft,
          ),
        ),
        Center(
          child: KioskOutlineButton(
            text: 'Done',
            onPressed: () => context.read<KioskFlowCubit>().closeAppModal(),
          ),
        ),
      ],
    );
  }
}
