import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_state.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_flow_foot.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_plan_card.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_plan_picked_banner.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_signup_step_scaffold.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_who_for.dart';
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
/// **After a pick, the step scrolls back to the top** so the confirmation
/// banner, the pinned person, and Continue are all in view — a member who taps
/// a card low in a tall grid otherwise gets no feedback and is stranded at the
/// bottom. In a group each person's turn also starts at the top.
///
/// The step only ever renders a warmed catalogue or its spinner. An empty
/// catalogue and a failed read are not empty states here — the cubit routes
/// both to a stop, because "no memberships" on a screen headed "Pick your
/// membership" is a dead end dressed as a choice.
class KioskPlanPickStep extends StatefulWidget {
  const KioskPlanPickStep({super.key});

  @override
  State<KioskPlanPickStep> createState() => _KioskPlanPickStepState();
}

class _KioskPlanPickStepState extends State<KioskPlanPickStep> {
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Return the body to the top. A pick animates (the member watches the
  /// confirmation slide up into view); a new person JUMPS (a fresh turn should
  /// simply start at the top, not appear to scroll).
  void _toTop({required bool animate}) {
    // Post-frame, so the scroll runs after the rebuild that added the banner /
    // swapped the person — a scroll issued against the old extent would be
    // clamped short.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      if (animate) {
        _scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutQuart,
        );
      } else {
        _scroll.jumpTo(0);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<KioskSignupCubit>();
    return BlocListener<KioskSignupCubit, KioskSignupState>(
      // A group advances person-by-person through the same step; each new turn
      // starts at the top.
      listenWhen: (prev, cur) =>
          prev.activePersonIndex != cur.activePersonIndex,
      listener: (_, _) => _toTop(animate: false),
      child: BlocBuilder<KioskSignupCubit, KioskSignupState>(
        buildWhen: (prev, cur) =>
            prev.plans != cur.plans ||
            prev.plansLoading != cur.plansLoading ||
            prev.persons != cur.persons ||
            prev.activePersonIndex != cur.activePersonIndex ||
            prev.activePerson.selectedPlanId != cur.activePerson.selectedPlanId,
        builder: (context, state) {
          final picked = state.activePerson.selectedPlanId;
          final pickedPlan = state.planById(picked);
          return KioskSignupStepScaffold(
            step: KioskSignupStep.plans,
            title: _title(state),
            subtitle: _subtitle(state),
            bodyController: _scroll,
            // Pinned, so it cannot scroll away behind the grid. In a group it
            // is the whole point of the screen: a parent picking three
            // memberships in a row must never buy the wrong one for the wrong
            // child. Solo there is only one person, and naming them would be an
            // odd thing to tell someone about themselves.
            identity: state.isGroup
                ? KioskWhoFor(
                    eyebrow: 'PICKING FOR',
                    name: _fullName(state),
                  )
                : null,
            foot: KioskFlowFoot(
              onPrimary: picked == null ? null : cubit.continueFromPlans,
              onBack: cubit.back,
            ),
            child: state.plansLoading && state.plans.isEmpty
                ? const _Loading()
                : _PlanGrid(
                    state: state,
                    picked: picked,
                    pickedPlanName: pickedPlan?.planName,
                    onPick: (planId) {
                      cubit.selectPlan(planId);
                      _toTop(animate: true);
                    },
                  ),
          );
        },
      ),
    );
  }

  /// The step is walked once per TRAINING person, so in a GROUP it names whose
  /// choice is on screen — **every turn, the payer's included.** An unnamed
  /// screen in the middle of a run of named ones is ambiguous exactly when it
  /// matters most, and the ambiguity is paid for with the wrong membership on
  /// the wrong person.
  ///
  /// Solo keeps the warm second person: there is only one person it could
  /// mean, and telling somebody their own name is a strange way to address
  /// them.
  String _title(KioskSignupState state) {
    if (!state.isGroup) return 'Pick your membership';
    final first = state.activePerson.firstName.trim();
    return first.isEmpty
        ? 'Pick their membership'
        : 'Pick $first\'s membership';
  }

  String _fullName(KioskSignupState state) {
    final person = state.activePerson;
    return '${person.firstName} ${person.lastName}'.trim();
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

/// The confirmation banner, then the plans three across on the kiosk stage,
/// over the one quiet pointer at the desk.
///
/// The pointer is deliberately NOT the app-adoption line + glyph pair: that
/// component means "get the app" everywhere else on this kiosk, and reusing it
/// for "ask a coach" would teach a member the wrong thing about it.
class _PlanGrid extends StatelessWidget {
  final KioskSignupState state;
  final String? picked;
  final String? pickedPlanName;
  final ValueChanged<String> onPick;

  const _PlanGrid({
    required this.state,
    required this.picked,
    required this.pickedPlanName,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingLarge,
      children: [
        if (pickedPlanName != null)
          KioskPlanPickedBanner(planName: pickedPlanName!),
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
                onTap: () => onPick(plan.planId),
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
