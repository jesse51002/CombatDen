import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/kiosk/bloc/kiosk_flow_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_flow_state.dart';
import 'package:crm/features/kiosk/presentation/kiosk_name_format.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_glance_foot.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_glance_greeting.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_rewards_panel.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_streak_panel.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_stage.dart';

/// The post-check-in retention "glance" — the member-facing money screen shown
/// once a check-in is recorded (mockup `glance` / `claim`). A celebratory
/// greeting over two panels — the streak (left) and the points + reward tiles
/// (right) — with an auto-return timer + Done below. A tap anywhere returns
/// home (wired at the kiosk surface). Its data (streak + earned points from the
/// check-in response; balance + reward catalog fetched by the cubit) rides on
/// [KioskFlowState]; it degrades gracefully when a fetch fails.
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
          prev.selectedMember != cur.selectedMember ||
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              spacing: DesignConstants.spacingMedium,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: DesignConstants.spacingBig,
                  children: [
                    KioskGlanceGreeting(
                      firstName: kioskFirstName(state.selectedMember?.name),
                      alreadyCheckedIn: alreadyCheckedIn,
                    ),
                    IntrinsicHeight(
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
                  ],
                ),
                KioskGlanceFoot(secondsLeft: state.glanceCountdown),
              ],
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
