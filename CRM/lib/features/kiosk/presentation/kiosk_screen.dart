import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/network/api_client.dart';
import 'package:crm/core/state/selected_gym.dart';
import 'package:crm/features/kiosk/bloc/kiosk_flow_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_flow_state.dart';
import 'package:crm/features/kiosk/bloc/kiosk_session_cubit.dart';
import 'package:crm/features/kiosk/presentation/kiosk_reveal_timings.dart';
import 'package:crm/features/kiosk/presentation/screens/kiosk_blocked_screen.dart';
import 'package:crm/features/kiosk/presentation/screens/kiosk_class_pick_screen.dart';
import 'package:crm/features/kiosk/presentation/screens/kiosk_closing_screen.dart';
import 'package:crm/features/kiosk/presentation/screens/kiosk_glance_screen.dart';
import 'package:crm/features/kiosk/presentation/screens/kiosk_home_screen.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_checking_in.dart';
import 'package:crm/features/kiosk/presentation/widgets/get_app/slides/kiosk_rank_slide.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_get_app_modal.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_header.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_idle_warning.dart';
import 'package:crm/features/member_details/data/repositories/member_repository.dart';
import 'package:crm/features/members/data/gym_content_repository.dart';
import 'package:crm/features/members_list/data/models/member_row.dart';
import 'package:crm/features/members_list/data/repositories/members_list_repository.dart';
import 'package:crm/features/memberships/data/repositories/ranks_repository.dart';
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
        gymContentRepository: GymContentRepository(ApiClient()),
        ranksRepository: RanksRepository(apiClient: ApiClient()),
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
                    _AppModalOverlay(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// A pointer-down anywhere on the kiosk surface: resets the 5-minute flow-idle
  /// guard ("I'm still here"). Harmless on the idle home and the retention
  /// glance (neither runs the guard). While the "Get the app" modal is open it
  /// is a no-op — the modal owns its own 60-second clock. The glance's
  /// tap-to-open-the-modal is handled by the glance screen's own gesture (so
  /// its Done button still wins its own taps), not here.
  void _onSurfaceTap(BuildContext context) {
    final cubit = context.read<KioskFlowCubit>();
    if (cubit.state.appModalOpen) return;
    cubit.registerActivity();
  }
}

/// The current kiosk sub-screen, cross-faded rather than hard-cut.
///
/// The swap that mattered is "Checking you in…" → the glance: a hard cut there
/// makes a recorded check-in feel like a page reload instead of a result, and
/// it is the one moment the member is watching for an answer. The fade lets
/// the spinner RESOLVE into the glance while the glance's own confirmation
/// beat is already running underneath. The tap itself is acknowledged before
/// any of this — `ClassCard` inks on press and the cubit emits the
/// checking-in view synchronously.
///
/// [KioskRevealTimings.element] is the same duration every other kiosk
/// entrance uses; reduced motion collapses it to an instant swap.
///
/// The layout builder mirrors AnimatedSwitcher's default but with
/// [StackFit.passthrough] and a top-left alignment, so each screen is laid out
/// under exactly the constraints it got before this wrapper existed — the
/// cross-fade is layout-transparent.
class _ViewSwitcher extends StatelessWidget {
  const _ViewSwitcher();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<KioskFlowCubit, KioskFlowState>(
      buildWhen: (prev, cur) => prev.view != cur.view,
      builder: (context, state) {
        final screen = switch (state.view) {
          KioskView.home => const KioskHomeScreen(),
          KioskView.classPick => const KioskClassPickScreen(),
          KioskView.checkingIn => const KioskCheckingIn(),
          KioskView.checkedIn => const KioskGlanceScreen(),
          KioskView.blocked => const KioskBlockedScreen(),
          KioskView.closing => const KioskClosingScreen(),
        };
        return AnimatedSwitcher(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : KioskRevealTimings.element,
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeOut,
          layoutBuilder: (currentChild, previousChildren) => Stack(
            alignment: Alignment.topLeft,
            fit: StackFit.passthrough,
            children: [...previousChildren, ?currentChild],
          ),
          child: KeyedSubtree(key: ValueKey(state.view), child: screen),
        );
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

/// The "Get the CombatDen App" modal (UX-5), rendered over the current view
/// (like the idle warning) whenever the cubit's [KioskFlowState.appModalOpen]
/// is set — opened by a glance tap or the home adopt strip's "Get it"
/// affordance.
///
/// Everything it shows comes from state the cubit ALREADY holds: the four
/// gym-wide catalogues warmed once at kiosk entry (rewards, the gym's upcoming
/// classes, its own video feed, its rank ladder) plus the checked-in member's
/// address. **No fetch is fired to open the modal** — that is what keeps it
/// instant. A catalogue that came back empty simply drops its slide.
///
/// The classes it renders are `showcaseClasses`, NOT the check-in flow's
/// `classes`: the flow's list is per-member and check-in-window filtered, so
/// wiring it here is what left the "Book classes" slide missing from the home
/// path (and would drop it every evening besides).
class _AppModalOverlay extends StatelessWidget {
  const _AppModalOverlay();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<KioskFlowCubit, KioskFlowState>(
      buildWhen: (prev, cur) =>
          prev.appModalOpen != cur.appModalOpen ||
          prev.appModalCountdown != cur.appModalCountdown ||
          prev.rewards != cur.rewards ||
          prev.showcaseClasses != cur.showcaseClasses ||
          prev.videos != cur.videos ||
          prev.rankLadder != cur.rankLadder ||
          prev.selectedMember != cur.selectedMember,
      builder: (context, state) {
        if (!state.appModalOpen) return const SizedBox.shrink();
        // Only the `all` view row carries an email, and that is the view the
        // kiosk name search uses; any other shape means we don't know it.
        final member = state.selectedMember;
        return KioskGetAppModal(
          gymId: selectedGym.gymId ?? '',
          gymName: selectedGym.gymName,
          secondsLeft: state.appModalCountdown,
          memberEmail: member is AllViewRow ? member.email : null,
          rewards: state.rewards,
          showcaseClasses: state.showcaseClasses,
          videos: state.videos,
          rankLadder: kioskRankSteps(state.rankLadder),
        );
      },
    );
  }
}
