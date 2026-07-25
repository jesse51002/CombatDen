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
import 'package:crm/features/kiosk/presentation/screens/kiosk_signup_screen.dart';
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
/// Hosts the check-in lane: a persistent header, the swapping sub-screen
/// ([KioskFlowCubit] drives which), and the flow-idle warning overlay. A tap
/// anywhere resets the 5-minute idle guard — except on the retention glance,
/// where it opens the Get-the-App modal instead, and while that modal is open,
/// where it does neither. The signup lane runs its own sibling cubit and its
/// own guard (see `KioskSignupScreen`).
class KioskScreen extends StatelessWidget {
  const KioskScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Fresh `ApiClient()` per repository, built where the cubit is (they are
    // not provided in the tree). The gym id is non-null: the auth gate only
    // mounts the kiosk once a gym is active.
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

  /// A pointer-down anywhere on the kiosk surface: resets the 5-minute
  /// flow-idle guard. A no-op while the "Get the app" modal is open — the
  /// modal owns its own clock. The glance's tap-to-open-the-modal is the
  /// glance's own gesture, not this one.
  void _onSurfaceTap(BuildContext context) {
    final cubit = context.read<KioskFlowCubit>();
    if (cubit.state.appModalOpen) return;
    cubit.registerActivity();
  }
}

/// The current kiosk sub-screen, cross-faded rather than hard-cut.
///
/// The swap that matters is "Checking you in…" → the glance: a hard cut there
/// reads as a page reload at the one moment the member is watching for an
/// answer, so the spinner RESOLVES into the glance. Reduced motion collapses
/// it to an instant swap.
///
/// The layout builder uses [StackFit.passthrough] and top-left alignment so
/// each screen keeps the constraints it would have without this wrapper — the
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
          // Provides its own `KioskSignupCubit`, so leaving this view
          // unmounts the subtree and disposes the typed PII structurally.
          KioskView.signup => const KioskSignupScreen(),
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

/// The "Get the app" modal, rendered over the current view whenever
/// [KioskFlowState.appModalOpen] is set. Everything it shows comes from state
/// the cubit already holds — the gym-wide catalogues warmed once at kiosk
/// entry — so no fetch is fired to open it, which is what keeps it instant. An
/// empty catalogue drops its slide.
///
/// It renders `showcaseClasses`, NOT the check-in flow's `classes`: that list
/// is per-member and check-in-window filtered, so wiring it here drops the
/// "Book classes" slide on the home path, and every evening besides.
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
