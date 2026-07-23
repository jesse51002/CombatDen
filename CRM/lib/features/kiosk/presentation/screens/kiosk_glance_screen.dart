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
/// DATA NOTE — week strip: the backend exposes no per-day completion source
/// (`GET /streak` and the check-in response return only an integer week count).
/// So the strip marks only TODAY (the just-checked-in day) done; a real
/// per-day strip needs a new backend field or a history query.
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
        return KioskStage(
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
                  ),
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: DesignConstants.spacingLarge,
                      children: [
                        Expanded(
                          child: KioskStreakPanel(
                            weeks: result?.classStreakWeeks ?? 0,
                            daysCompleted: _todayOnly(),
                          ),
                        ),
                        Expanded(
                          child: KioskRewardsPanel(
                            pointsBalance: state.pointsBalance,
                            pointsAwarded: result?.pointsAwarded ?? 0,
                            rewards: state.rewards,
                            loading: state.glanceLoading,
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
        );
      },
    );
  }

  /// Sun..Sat completion with only TODAY marked done — the one day we KNOW was
  /// attended (the check-in that produced this glance). See the class doc's data
  /// note: no per-day source exists to fill the rest honestly.
  static List<bool> _todayOnly() {
    final todayIndex = DateTime.now().weekday % 7; // Mon=1..Sun=7 -> Sun=0
    return List<bool>.generate(7, (i) => i == todayIndex);
  }
}
