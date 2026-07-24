import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/network/api_client.dart';
import 'package:crm/core/state/selected_gym.dart';
import 'package:crm/features/kiosk/bloc/kiosk_flow_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_session_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_state.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_idle_warning.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_abandon_confirm.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_card_step.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_declined_screen.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_match_step.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_payer_waiver_step.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_paying_screen.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_people_step.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_plan_pick_step.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_review_step.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_signup_details_step.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_signup_optional_step.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_signup_stop_screen.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_waiver_step.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_welcome_screen.dart';
import 'package:crm/features/member_details/data/repositories/member_repository.dart';
import 'package:crm/features/members_list/data/repositories/members_list_repository.dart';
import 'package:crm/features/memberships/data/repositories/memberships_repository.dart';

/// The member-facing SELF-SERVE SIGNUP lane, mounted by `KioskScreen`'s view
/// switcher when the home's "Sign up" starts one.
///
/// **It provides its own `KioskSignupCubit`, and that is load-bearing**: the
/// cubit's lifetime is therefore exactly the flow's lifetime. Leaving the view
/// (any `KioskFlowCubit.goHome()`) unmounts this subtree, `close()` runs, and
/// every typed field — name, address, emergency contact, and later the card —
/// is disposed structurally rather than by remembering to clear it. That is
/// the shared-iPad privacy rule made a property of the tree.
///
/// It also hosts its OWN activity listener. `KioskScreen`'s body-level
/// `Listener` reads `KioskFlowCubit`, which is provided ABOVE this subtree, so
/// it cannot reach a cubit provided down here — a signup-lane tap has to be
/// registered against the signup lane's own 5-minute guard.
class KioskSignupScreen extends StatelessWidget {
  const KioskSignupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Repositories follow the kiosk convention: instantiated with a fresh
    // `ApiClient()` where the cubit is built. The gym id is guaranteed
    // non-null — the auth gate only mounts the kiosk once a gym is active.
    return BlocProvider<KioskSignupCubit>(
      create: (context) => KioskSignupCubit(
        memberRepository: MemberRepository(apiClient: ApiClient()),
        membershipsRepository: MembershipsRepository(apiClient: ApiClient()),
        membersListRepository: MembersListRepository(apiClient: ApiClient()),
        session: context.read<KioskSessionCubit>(),
        gymId: selectedGym.gymId!,
      ),
      child: const _KioskSignupBody(),
    );
  }
}

class _KioskSignupBody extends StatelessWidget {
  const _KioskSignupBody();

  @override
  Widget build(BuildContext context) {
    return BlocListener<KioskSignupCubit, KioskSignupState>(
      // The cubit cannot navigate — `goHome()` is `KioskFlowCubit`'s, and it
      // is the kiosk's ONE abandon path. So every signup exit (the escape,
      // the confirmed start-over, the idle timeout, both stop-screen exits)
      // raises `abandoned` and lands here. The cubit has already released the
      // session flow count by this point; `goHome()` re-releases nothing
      // (its own latch is separate and was never started for a signup).
      listenWhen: (prev, cur) => !prev.abandoned && cur.abandoned,
      listener: (context, _) => context.read<KioskFlowCubit>().goHome(),
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) =>
            context.read<KioskSignupCubit>().registerActivity(),
        child: Stack(
          children: const [
            _StepSwitcher(),
            _SignupIdleOverlay(),
            _AbandonOverlay(),
          ],
        ),
      ),
    );
  }
}

/// The current signup step.
class _StepSwitcher extends StatelessWidget {
  const _StepSwitcher();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<KioskSignupCubit, KioskSignupState>(
      // `payerAuthPending` splits ONE step across two screens: the waiver rung
      // covers both the payer-auth link and the liability waivers, because to
      // the member they are one act — signing — and a rail that grew a rung
      // per payee would stop advertising an honest length for a family.
      buildWhen: (prev, cur) =>
          prev.step != cur.step ||
          prev.payerAuthPending != cur.payerAuthPending,
      builder: (context, state) {
        return switch (state.step) {
          KioskSignupStep.details => const KioskSignupDetailsStep(),
          // ONE widget, parameterized by the active person: the payer's own
          // optional block and every payee's are the same screen.
          KioskSignupStep.extraDetails => const KioskSignupOptionalStep(),
          KioskSignupStep.personDetails => const KioskSignupOptionalStep(),
          KioskSignupStep.stop => const KioskSignupStopScreen(),
          KioskSignupStep.people => const KioskPeopleStep(),
          KioskSignupStep.match => const KioskMatchStep(),
          KioskSignupStep.plans => const KioskPlanPickStep(),
          KioskSignupStep.waivers => state.payerAuthPending
              ? const KioskPayerWaiverStep()
              : const KioskWaiverStep(),
          KioskSignupStep.card => const KioskCardStep(),
          KioskSignupStep.review => const KioskReviewStep(),
          KioskSignupStep.paying => const KioskPayingScreen(),
          KioskSignupStep.declined => const KioskDeclinedScreen(),
          KioskSignupStep.welcome => const KioskWelcomeScreen(),
        };
      },
    );
  }
}

/// The signup lane's idle warning. Same widget the check-in lane uses, routed
/// to THIS cubit's `registerActivity` — the lane runs its own 5-minute guard,
/// so "I'm still here" has to answer the clock that is actually running.
class _SignupIdleOverlay extends StatelessWidget {
  const _SignupIdleOverlay();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<KioskSignupCubit, KioskSignupState>(
      buildWhen: (prev, cur) =>
          prev.idleWarningActive != cur.idleWarningActive ||
          prev.idleCountdown != cur.idleCountdown,
      builder: (context, state) {
        if (!state.idleWarningActive) return const SizedBox.shrink();
        return KioskIdleWarning(
          seconds: state.idleCountdown,
          onStillHere: () =>
              context.read<KioskSignupCubit>().registerActivity(),
        );
      },
    );
  }
}

/// The "Start over?" confirmation, over whichever step raised it.
class _AbandonOverlay extends StatelessWidget {
  const _AbandonOverlay();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<KioskSignupCubit, KioskSignupState>(
      buildWhen: (prev, cur) =>
          prev.abandonConfirmActive != cur.abandonConfirmActive,
      builder: (context, state) {
        if (!state.abandonConfirmActive) return const SizedBox.shrink();
        return const KioskAbandonConfirm();
      },
    );
  }
}
