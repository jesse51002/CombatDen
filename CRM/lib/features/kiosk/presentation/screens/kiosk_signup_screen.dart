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
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_entry_choice_step.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_identify_step.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_match_step.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_payer_match_step.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_payer_pick_step.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_payer_waiver_step.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_plan_block.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_paying_screen.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_people_step.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_plan_pick_step.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_remove_confirm.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_results_screen.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_review_step.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_signup_details_step.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_signup_optional_step.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_signup_stop_screen.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_waiver_step.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_welcome_screen.dart';
import 'package:crm/features/member_details/data/repositories/member_repository.dart';
import 'package:crm/features/members_list/data/repositories/members_list_repository.dart';
import 'package:crm/features/membership_flow/config/kiosk_flow_copy.dart';
import 'package:crm/features/membership_flow/config/membership_flow_scale.dart';
import 'package:crm/features/membership_flow/config/membership_flow_theme.dart';
import 'package:crm/features/memberships/data/repositories/memberships_repository.dart';

/// The member-facing SELF-SERVE SIGNUP lane, mounted by `KioskScreen`'s view
/// switcher when the home's "Start Trial / Membership" starts one.
///
/// It provides its own `KioskSignupCubit`, and that is load-bearing: the
/// cubit's lifetime is exactly the flow's, so leaving the view unmounts this
/// subtree and disposes every typed field — name, address, emergency contact,
/// card — structurally rather than by remembering to clear it. The shared-iPad
/// privacy rule, made a property of the tree.
///
/// It hosts its OWN activity listener too: `KioskScreen`'s body-level
/// `Listener` reads `KioskFlowCubit`, provided ABOVE this subtree, so a signup
/// tap must answer the guard actually running down here.
///
/// It is also the SURFACE that names its own scale and its own voice: the
/// shared flow components carry neither a size nor a sentence of their own and
/// read [MembershipFlowTheme] instead, so the host mounts
/// `MembershipFlowScale.kiosk()` + `KioskFlowCopy` once, above the step
/// switcher and every overlay. Nothing below names a surface again.
class KioskSignupScreen extends StatelessWidget {
  const KioskSignupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Fresh `ApiClient()` per repository, as elsewhere in the kiosk. The gym
    // id is non-null: the kiosk only mounts once a gym is active.
    return BlocProvider<KioskSignupCubit>(
      create: (context) => KioskSignupCubit(
        memberRepository: MemberRepository(apiClient: ApiClient()),
        membershipsRepository: MembershipsRepository(apiClient: ApiClient()),
        membersListRepository: MembersListRepository(apiClient: ApiClient()),
        session: context.read<KioskSessionCubit>(),
        gymId: selectedGym.gymId!,
      ),
      child: const MembershipFlowTheme(
        scale: MembershipFlowScale.kiosk(),
        copy: KioskFlowCopy(),
        child: _KioskSignupBody(),
      ),
    );
  }
}

class _KioskSignupBody extends StatelessWidget {
  const _KioskSignupBody();

  @override
  Widget build(BuildContext context) {
    return BlocListener<KioskSignupCubit, KioskSignupState>(
      // The cubit cannot navigate — `goHome()` is `KioskFlowCubit`'s, and the
      // kiosk's ONE abandon path — so every signup exit raises `abandoned`
      // and lands here. The cubit has already released the session flow count
      // by now; `goHome()`'s own latch is separate and re-releases nothing.
      listenWhen: (prev, cur) => !prev.abandoned && cur.abandoned,
      listener: (context, _) => context.read<KioskFlowCubit>().goHome(),
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) =>
            context.read<KioskSignupCubit>().registerActivity(),
        child: Stack(
          children: const [
            _StepSwitcher(),
            _PlanBlockOverlay(),
            _SignupIdleOverlay(),
            _AbandonOverlay(),
            _RemoveOverlay(),
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
      // `payerAuthPending` splits ONE step across two screens: to the member,
      // the payer-auth link and the liability waivers are one act — signing —
      // and a rail that grew a rung per payee would stop advertising an
      // honest length for a family.
      buildWhen: (prev, cur) =>
          prev.step != cur.step ||
          prev.payerAuthPending != cur.payerAuthPending,
      builder: (context, state) {
        return switch (state.step) {
          KioskSignupStep.entry => const KioskEntryChoiceStep(),
          KioskSignupStep.identify => const KioskIdentifyStep(),
          KioskSignupStep.details => const KioskSignupDetailsStep(),
          // ONE widget, parameterized by the active person: the payer's own
          // optional block and every payee's are the same screen.
          KioskSignupStep.extraDetails => const KioskSignupOptionalStep(),
          KioskSignupStep.personDetails => const KioskSignupOptionalStep(),
          KioskSignupStep.stop => const KioskSignupStopScreen(),
          KioskSignupStep.people => const KioskPeopleStep(),
          KioskSignupStep.match => const KioskMatchStep(),
          KioskSignupStep.payerMatch => const KioskPayerMatchStep(),
          KioskSignupStep.payerPick => const KioskPayerPickStep(),
          KioskSignupStep.plans => const KioskPlanPickStep(),
          KioskSignupStep.waivers => state.payerAuthPending
              ? const KioskPayerWaiverStep()
              : const KioskWaiverStep(),
          KioskSignupStep.card => const KioskCardStep(),
          KioskSignupStep.review => const KioskReviewStep(),
          KioskSignupStep.paying => const KioskPayingScreen(),
          // The landed start, itemised — covers all-created AND a partial. An
          // ALL-failed start goes to the decline popup instead, the one place
          // "nothing was charged" is true.
          KioskSignupStep.results => const KioskResultsScreen(),
          KioskSignupStep.declined => const KioskDeclinedScreen(),
          KioskSignupStep.welcome => const KioskWelcomeScreen(),
        };
      },
    );
  }
}

/// Why a plan card cannot be picked, over the grid that raised it — one popup
/// for both reasons (a trial already used, a membership already held). An
/// OVERLAY rather than a step, so the grid stays live behind it: nothing to
/// re-fetch, no scroll position to restore, and the rail keeps its honest
/// length.
class _PlanBlockOverlay extends StatelessWidget {
  const _PlanBlockOverlay();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<KioskSignupCubit, KioskSignupState>(
      buildWhen: (prev, cur) => prev.planBlockActive != cur.planBlockActive,
      builder: (context, state) {
        if (state.planBlockActive == null) return const SizedBox.shrink();
        return const KioskPlanBlock();
      },
    );
  }
}

/// The signup lane's idle warning — the check-in lane's widget routed to THIS
/// cubit's `registerActivity`, so "I'm still here" answers the clock that is
/// actually running.
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

/// The roster's "take them off this signup?" confirmation.
class _RemoveOverlay extends StatelessWidget {
  const _RemoveOverlay();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<KioskSignupCubit, KioskSignupState>(
      buildWhen: (prev, cur) =>
          prev.removeConfirmIndex != cur.removeConfirmIndex,
      builder: (context, state) {
        final index = state.removeConfirmIndex;
        if (index == null || index >= state.persons.length) {
          return const SizedBox.shrink();
        }
        final person = state.persons[index];
        return KioskRemoveConfirm(
          name: '${person.firstName} ${person.lastName}'.trim(),
          asksNextPayer: person.isPayer,
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
