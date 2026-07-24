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
/// once a check-in is recorded (mockup `glance` / `claim`). A one-line
/// confirmation over two panels — the streak (left) and the points + reward
/// tiles (right) — with an auto-return timer + Done below. A tap anywhere
/// returns home (wired at the kiosk surface). Its data (streak + earned points
/// from the check-in response; balance + reward catalog fetched by the cubit)
/// rides on [KioskFlowState]; it degrades gracefully when a fetch fails.
///
/// **It arrives in two beats, and the order is the hierarchy**
/// ([KioskRevealTimings]): the CONFIRMATION fades in first and does it CENTRED
/// on the stage, alone (the check disc popping in beside the named class — the
/// answer to "did it work, and into what?"), holds there, then travels up into
/// its slot at the top ([KioskGlanceLift]); BOTH cards — the streak with its
/// numeral rolling up, and the rewards with its tiles cascading in one by one
/// — then land together under one reveal. Everything arriving at once was
/// cognitive overload (founder ruling), so the answer gets the screen to
/// itself first and the payout follows as a pair. The footer's ten-second hold
/// clock only starts at the LAST beat (`kKioskGlanceLastBeat`) so the reveal
/// never eats the reading time. A reduced-motion viewer gets every beat at
/// once, already landed.
///
/// The week strip reads `current_week_days` (Monday-first, index 0 = Monday)
/// off the check-in response — one badge per weekday attended this week.
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
        // A tap ANYWHERE on the glance opens the "Get the app" modal (the
        // founder's UX-5 ruling — the glance tap now funnels to the app instead
        // of ejecting home). The Done button + reward tiles are interactive
        // children that win their own taps in the gesture arena, so this only
        // fires on the glance's inert areas. Opaque so the whole glance surface
        // is tappable.
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => context.read<KioskFlowCubit>().openAppModal(),
          child: KioskStage(
            child: KioskGlanceLift(
              spacing: DesignConstants.spacingBig,
              // Beat 1 — did it work, and which class. Centred and alone for
              // three seconds, then lifted into this slot by KioskGlanceLift.
              confirmation: KioskReveal(
                delay: KioskRevealTimings.confirmation,
                duration: KioskRevealTimings.confirmationFade,
                child: KioskGlanceGreeting(
                  className: state.selectedClassName,
                  alreadyCheckedIn: alreadyCheckedIn,
                ),
              ),
              // Laid out in full from the first frame — invisible, but holding
              // every pixel it will hold at the end, so the two panels arriving
              // later reflow nothing and Done never moves.
              rest: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                spacing: DesignConstants.spacingMedium,
                children: [
                  // Beat 2 — the payout. ONE reveal around BOTH cards, so the
                  // streak and the rewards land together by construction
                  // rather than by two offsets that happen to agree.
                  KioskReveal(
                    delay: KioskRevealTimings.panels,
                    child: IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        spacing: DesignConstants.spacingLarge,
                        children: [
                          // The streak — its numeral counts up as it lands.
                          Expanded(
                            child: KioskStreakPanel(
                              weeks: result?.classStreakWeeks ?? 0,
                              daysCompleted:
                                  result?.currentWeekDays ?? _kEmptyWeek,
                            ),
                          ),
                          // The rewards — its tiles cascading inside.
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
