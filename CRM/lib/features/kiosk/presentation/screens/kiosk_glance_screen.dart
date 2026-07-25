import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/kiosk/bloc/kiosk_flow_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_flow_state.dart';
import 'package:crm/features/kiosk/presentation/kiosk_reveal_timings.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_glance_foot.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_glance_greeting.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_glance_lift.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_reveal.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_rewards_panel.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_streak_panel.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_stage.dart';

/// The post-check-in retention "glance" — the member-facing money screen shown
/// once a check-in is recorded: a one-line confirmation over two panels, the
/// streak (left) and the points + reward tiles (right), with an auto-return
/// timer + Done below. A tap anywhere opens the "Get the app" modal. Its data
/// (streak + points from the check-in response; balance + reward catalog
/// fetched by the cubit) rides on [KioskFlowState] and degrades gracefully
/// when a fetch fails.
///
/// It arrives in TWO beats — the confirmation alone, then both cards together
/// — choreographed by [KioskRevealTimings], which owns that ordering and why.
/// The footer's hold clock only starts at the LAST beat so the reveal never
/// eats the reading time; a reduced-motion viewer gets every beat at once,
/// already landed.
///
/// The week strip reads `current_week_days` (Monday-first, index 0 = Monday) —
/// one badge per weekday attended this week.
class KioskGlanceScreen extends StatelessWidget {
  const KioskGlanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<KioskFlowCubit, KioskFlowState>(
      buildWhen: (prev, cur) =>
          prev.checkInResult != cur.checkInResult ||
          prev.selectedClassName != cur.selectedClassName ||
          prev.pointsBalance != cur.pointsBalance ||
          prev.rewards != cur.rewards ||
          prev.glanceLoading != cur.glanceLoading ||
          prev.glanceCountdown != cur.glanceCountdown,
      builder: (context, state) {
        final result = state.checkInResult;
        final alreadyCheckedIn = result?.alreadyCheckedIn ?? false;
        // A tap ANYWHERE opens the "Get the app" modal (founder ruling: the
        // glance tap funnels to the app rather than ejecting home). Done and
        // the reward tiles win their own taps, so this fires only on the
        // glance's inert areas.
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => context.read<KioskFlowCubit>().openAppModal(),
          child: KioskStage(
            child: KioskGlanceLift(
              spacing: DesignConstants.spacingBig,
              // Beat 1 — did it work, and which class. Centred and alone,
              // then lifted into this slot by KioskGlanceLift.
              confirmation: KioskReveal(
                delay: KioskRevealTimings.confirmation,
                duration: KioskRevealTimings.confirmationFade,
                child: KioskGlanceGreeting(
                  className: state.selectedClassName,
                  alreadyCheckedIn: alreadyCheckedIn,
                ),
              ),
              // Laid out in full from the first frame — invisible, but already
              // holding every pixel it will hold, so the panels arriving later
              // reflow nothing and Done never moves.
              rest: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                spacing: DesignConstants.spacingMedium,
                children: [
                  // Beat 2 — the payout. ONE reveal around BOTH cards, so they
                  // land together by construction, not by two offsets that
                  // happen to agree.
                  KioskReveal(
                    delay: KioskRevealTimings.panels,
                    child: IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        spacing: DesignConstants.spacingLarge,
                        children: [
                          Expanded(
                            child: KioskStreakPanel(
                              weeks: result?.classStreakWeeks ?? 0,
                              daysCompleted:
                                  result?.currentWeekDays ?? _kEmptyWeek,
                            ),
                          ),
                          Expanded(
                            child: KioskRewardsPanel(
                              pointsBalance: state.pointsBalance,
                              pointsAwarded: result?.pointsAwarded ?? 0,
                              rewards: state.rewards,
                              loading: state.glanceLoading,
                              alreadyCheckedIn: alreadyCheckedIn,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  KioskGlanceFoot(secondsLeft: state.glanceCountdown),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A length-7 all-false week — the fall-back passed to the strip before any
/// check-in result is present (index 0 = Monday … 6 = Sunday).
const List<bool> _kEmptyWeek = [
  false,
  false,
  false,
  false,
  false,
  false,
  false,
];
