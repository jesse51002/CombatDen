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
/// side by side, over the popup's own timer + Done foot — the foot belongs to
/// the surface, not floating under it (founder ruling).
///
/// It NEVER scrolls: the foot lays out first and the cards take an [Expanded]
/// share of what is left, so each card's `ShrinkToFit` turns a too-short fold
/// into one proportional scale-down instead of an overflow. Never add a
/// scroll view here — a scrollbar on a kiosk is content nobody will see.
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
        Expanded(
          child: slides.isEmpty
              // A gym with nothing to show yet: the app card carries the popup
              // alone rather than an empty second card or a stand-in slide.
              ? Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: DesignConstants.dialogMaxWidth,
                    ),
                    child: card,
                  ),
                )
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
/// Done hands the member back to whatever the overlay covered; the countdown
/// running out means nobody is there and goes home instead. That split is
/// [KioskFlowCubit]'s — this button only asks for it.
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
