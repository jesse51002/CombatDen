import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/home/presentation/layouts/home_layout_data.dart';
import 'package:mobile_app/features/home/presentation/layouts/parts/home_topbar.dart';
import 'package:mobile_app/features/home/presentation/widgets/class_schedule/class_schedule_title.dart';
import 'package:mobile_app/features/home/presentation/widgets/upcoming_sessions/upcoming_sessions_card.dart';

/// What sits above the date rail: the topbar, and — on the booked page
/// only — the upcoming-sessions card and the schedule title.
///
/// The booked/not-booked split is the pre-existing state difference
/// between home's two pages. It is the same in every format; only
/// [bleed] (whether the card runs to the screen edge) is a format's
/// call.
class HomeHeader extends StatelessWidget {
  const HomeHeader({super.key, required this.data, this.bleed = false});

  final HomeLayoutData data;
  final bool bleed;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingBig,
      children: [
        const HomeTopbar(),
        if (data.booked)
          if (bleed)
            const UpcomingSessionsCard()
          else
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: DesignConstants.screenHorizontalPadding,
              ),
              child: const UpcomingSessionsCard(),
            ),
        if (data.booked) const ClassScheduleTitle(),
      ],
    );
  }
}
