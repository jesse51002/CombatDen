import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_state.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_flow_foot.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_plan_card.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_signup_step_scaffold.dart';
import 'package:crm/shared/widgets/app_spinner.dart';
import 'package:crm/shared/widgets/fill_grid.dart';

/// D3 — pick a membership.
///
/// The grid is the shipped `KioskClassGrid` pattern (`FillGrid` over
/// hero-topped cards), so the two things a member picks on this kiosk — a
/// class and a plan — are picked from the same object at the same scale.
///
/// **One plan per person, single-select, always `quantity: 1`.** There is no
/// stepper: a self-serve iPad sells one membership to one person, and a
/// quantity control beside a price is a way to mis-tap into a bigger charge.
///
/// The step only ever renders a warmed catalogue or its spinner. An empty
/// catalogue and a failed read are not empty states here — the cubit routes
/// both to a stop, because "no memberships" on a screen headed "Pick your
/// membership" is a dead end dressed as a choice.
class KioskPlanPickStep extends StatelessWidget {
  const KioskPlanPickStep({super.key});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<KioskSignupCubit>();
    return BlocBuilder<KioskSignupCubit, KioskSignupState>(
      buildWhen: (prev, cur) =>
          prev.plans != cur.plans ||
          prev.plansLoading != cur.plansLoading ||
          prev.activePersonIndex != cur.activePersonIndex ||
          prev.activePerson.selectedPlanId != cur.activePerson.selectedPlanId,
      builder: (context, state) {
        final picked = state.activePerson.selectedPlanId;
        return KioskSignupStepScaffold(
          step: KioskSignupStep.plans,
          title: _title(state),
          subtitle: _subtitle(state),
          foot: KioskFlowFoot(
            onPrimary: picked == null ? null : cubit.continueFromPlans,
            onBack: cubit.back,
          ),
          child: state.plansLoading && state.plans.isEmpty
              ? const _Loading()
              : _PlanGrid(state: state, picked: picked),
        );
      },
    );
  }

  /// The step is walked once per TRAINING person, so it names whose choice is
  /// on screen — a parent picking three memberships in a row must never be
  /// able to buy the wrong one for the wrong child.
  String _title(KioskSignupState state) {
    if (state.activePersonIndex == 0) return 'Pick your membership';
    final first = state.activePerson.firstName.trim();
    return first.isEmpty
        ? 'Pick their membership'
        : 'Pick $first\'s membership';
  }

  String _subtitle(KioskSignupState state) {
    const rule = 'You can change it any time at the front desk · no lock-in';
    final order = state.trainingPersonIndexes;
    if (order.length < 2) return rule;
    final at = order.indexOf(state.activePersonIndex);
    return 'Person ${at + 1} of ${order.length} · $rule';
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(DesignConstants.paddingBig),
      child: Center(child: AppSpinner()),
    );
  }
}

/// The plans, three across on the kiosk stage, over the one quiet pointer at
/// the desk.
///
/// The pointer is deliberately NOT the app-adoption line + glyph pair: that
/// component means "get the app" everywhere else on this kiosk, and reusing it
/// for "ask a coach" would teach a member the wrong thing about it.
class _PlanGrid extends StatelessWidget {
  final KioskSignupState state;
  final String? picked;

  const _PlanGrid({required this.state, required this.picked});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<KioskSignupCubit>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingLarge,
      children: [
        FillGrid(
          // A floor of two columns and a 300px minimum lands three across on
          // the kiosk stage while a narrower fold degrades to two, exactly as
          // the class grid does.
          minItemWidth: 300,
          minColumns: 2,
          children: [
            for (final plan in state.plans)
              KioskPlanCard(
                plan: plan,
                selected: plan.planId == picked,
                onTap: () => cubit.selectPlan(plan.planId),
              ),
          ],
        ),
        Text(
          'Not sure which one? The front desk will talk you through it.',
          style: DesignConstants.kioskCaption.copyWith(
            color: DesignConstants.text2nd,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
