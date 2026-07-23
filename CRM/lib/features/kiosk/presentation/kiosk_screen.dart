import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/network/api_client.dart';
import 'package:crm/core/state/selected_gym.dart';
import 'package:crm/features/kiosk/bloc/kiosk_flow_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_flow_state.dart';
import 'package:crm/features/kiosk/bloc/kiosk_session_cubit.dart';
import 'package:crm/features/kiosk/presentation/screens/kiosk_blocked_screen.dart';
import 'package:crm/features/kiosk/presentation/screens/kiosk_class_pick_screen.dart';
import 'package:crm/features/kiosk/presentation/screens/kiosk_closing_screen.dart';
import 'package:crm/features/kiosk/presentation/screens/kiosk_glance_screen.dart';
import 'package:crm/features/kiosk/presentation/screens/kiosk_home_screen.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_checking_in.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_header.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_idle_warning.dart';
import 'package:crm/features/member_details/data/repositories/member_repository.dart';
import 'package:crm/features/members_list/data/repositories/members_list_repository.dart';
import 'package:crm/features/rewards/data/repositories/rewards_repository.dart';
import 'package:crm/features/schedule/data/repositories/schedule_repository.dart';

/// The full-viewport member surface mounted (in place of the admin workspace)
/// while kiosk is active — no `AppShell`, no nav rail, no admin routes.
///
/// It hosts the check-in lane: a persistent header, the swapping sub-screen
/// ([KioskFlowCubit] drives which), and the flow-idle warning overlay. The
/// whole surface listens for pointer activity — a tap resets the 5-minute idle
/// guard everywhere except the retention glance, where it dismisses to home.
///
/// The Phase C2 retention glance (streak + rewards) is live; the Phase D signup
/// flow is still a front-desk placeholder dialog.
class KioskScreen extends StatelessWidget {
  const KioskScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Repositories follow the CRM convention: instantiated with a fresh
    // `ApiClient()` at the point the cubit is built (they are not provided in
    // the widget tree). The gym id is guaranteed non-null here — the auth gate
    // only mounts the kiosk once a gym is active.
    return BlocProvider<KioskFlowCubit>(
      create: (context) => KioskFlowCubit(
        membersRepository: MembersListRepository(apiClient: ApiClient()),
        scheduleRepository: ScheduleRepository(apiClient: ApiClient()),
        memberRepository: MemberRepository(apiClient: ApiClient()),
        rewardsRepository: RewardsRepository(apiClient: ApiClient()),
        session: context.read<KioskSessionCubit>(),
        gymId: selectedGym.gymId!,
      ),
      child: const _KioskScreenBody(),
    );
  }
}

class _KioskScreenBody extends StatelessWidget {
  const _KioskScreenBody();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DesignConstants.backgroundColor,
      body: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _onSurfaceTap(context),
        child: SafeArea(
          child: Column(
            children: [
              const KioskHeader(),
              Expanded(
                child: Stack(
                  children: const [
                    _ViewSwitcher(),
                    _IdleOverlay(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// A pointer-down anywhere on the kiosk surface. On the retention glance
  /// (the flow has already ended) a tap DISMISSES to home so the next member
  /// gets a clean start; everywhere else it merely resets the 5-minute
  /// flow-idle guard ("I'm still here").
  void _onSurfaceTap(BuildContext context) {
    final cubit = context.read<KioskFlowCubit>();
    if (cubit.state.view == KioskView.checkedIn) {
      cubit.goHome();
    } else {
      cubit.registerActivity();
    }
  }
}

class _ViewSwitcher extends StatelessWidget {
  const _ViewSwitcher();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<KioskFlowCubit, KioskFlowState>(
      buildWhen: (prev, cur) => prev.view != cur.view,
      builder: (context, state) {
        return switch (state.view) {
          KioskView.home => const KioskHomeScreen(),
          KioskView.classPick => const KioskClassPickScreen(),
          KioskView.checkingIn => const KioskCheckingIn(),
          KioskView.checkedIn => const KioskGlanceScreen(),
          KioskView.blocked => const KioskBlockedScreen(),
          KioskView.closing => const KioskClosingScreen(),
        };
      },
    );
  }
}

class _IdleOverlay extends StatelessWidget {
  const _IdleOverlay();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<KioskFlowCubit, KioskFlowState>(
      buildWhen: (prev, cur) =>
          prev.idleWarningActive != cur.idleWarningActive ||
          prev.idleCountdown != cur.idleCountdown,
      builder: (context, state) {
        if (!state.idleWarningActive) return const SizedBox.shrink();
        return KioskIdleWarning(seconds: state.idleCountdown);
      },
    );
  }
}
