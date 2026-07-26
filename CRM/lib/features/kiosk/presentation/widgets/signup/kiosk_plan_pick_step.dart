import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_state.dart';
import 'package:crm/features/kiosk/presentation/kiosk_plan_block_copy.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_step_scaffold.dart';
import 'package:crm/features/member_details/data/models/membership_plan_response.dart';
import 'package:crm/features/membership_flow/presentation/chrome/flow_foot.dart';
import 'package:crm/features/membership_flow/presentation/chrome/flow_who_for.dart';
import 'package:crm/features/membership_flow/presentation/widgets/flow_inline_notice.dart';
import 'package:crm/features/membership_flow/presentation/widgets/flow_plan_card.dart';
import 'package:crm/features/membership_flow/presentation/widgets/flow_plan_picked_banner.dart';
import 'package:crm/shared/widgets/app_spinner.dart';
import 'package:crm/shared/widgets/fill_grid.dart';

/// D3 — pick a membership.
///
/// The grid is the shipped `KioskClassGrid` pattern (`FillGrid` over
/// hero-topped cards), so a class and a plan are picked from the same object.
///
/// One plan per person, single-select, always `quantity: 1`: there is no
/// stepper, because a quantity control beside a price is a way to mis-tap into
/// a bigger charge. In a group each person's turn starts at the top of the
/// grid; a pick itself does not scroll (see `_toTop`).
///
/// The step only ever renders a warmed catalogue or its spinner. An empty
/// catalogue and a failed read are not empty states here — the cubit routes
/// both to a stop, because "no memberships" under "Pick your membership" is a
/// dead end dressed as a choice.
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

  /// Return the body to the top when the PERSON changes, so each turn of a
  /// group starts fresh rather than inheriting the last person's scroll. It
  /// jumps rather than animates: nothing moved, the screen is simply new.
  ///
  /// A pick deliberately does NOT scroll (founder ruling) — returning to the
  /// top on selection yanks the grid out from under someone still comparing
  /// cards, and their tap is already confirmed in place.
  void _toTop() {
    // Post-frame, so the scroll runs after the rebuild that swapped the
    // person — against the old extent it would be clamped short.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(0);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<KioskSignupCubit>();
    return BlocListener<KioskSignupCubit, KioskSignupState>(
      listenWhen: (prev, cur) =>
          prev.activePersonIndex != cur.activePersonIndex,
      listener: (_, _) => _toTop(),
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
          return KioskStepScaffold(
            step: KioskSignupStep.plans,
            title: _title(state),
            subtitle: _subtitle(state),
            bodyController: _scroll,
            // Pinned so it cannot scroll away: a parent picking three
            // memberships in a row must never buy the wrong one for the wrong
            // child. Solo has only one person to mean, so it is omitted.
            identity: state.isGroup
                ? FlowWhoFor(
                    eyebrow: 'PICKING FOR',
                    name: _fullName(state),
                  )
                : null,
            foot: FlowFoot(
              onPrimary: picked == null ? null : cubit.continueFromPlans,
              onBack: cubit.back,
              // Skip is GROUP-only (founder ruling): skipping the sole person
              // of a solo signup would empty the cart, and at least one person
              // must get a membership. Skipping everybody returns to the
              // roster — see `KioskSignupCubit.skipPlanForPerson`.
              onSkip: state.isGroup ? cubit.skipPlanForPerson : null,
              skipLabel: 'Skip',
              onEscape: cubit.abandon,
            ),
            child: state.plansLoading && state.plans.isEmpty
                ? const _Loading()
                : _PlanGrid(
                    state: state,
                    picked: picked,
                    pickedPlanName: pickedPlan?.planName,
                    onPick: cubit.selectPlan,
                  ),
          );
        },
      ),
    );
  }

  /// The step is walked once per TRAINING person, so in a GROUP the title names
  /// whose choice is on screen — every turn, the payer's included. An unnamed
  /// turn in a run of named ones is paid for with the wrong membership on the
  /// wrong person. Solo keeps the second person.
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
/// That pointer is deliberately NOT the app-adoption line + glyph pair, which
/// means "get the app" everywhere else on this kiosk.
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
    final held = kioskHeldPlanNotice(state);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingLarge,
      children: [
        // Context first, then the pick just made. The notice NAMES the
        // membership this person already holds, so a marked card has its answer
        // above it and not only behind a tap; it is self-gating.
        if (held != null) FlowInlineNotice(message: held),
        if (pickedPlanName != null)
          FlowPlanPickedBanner(planName: pickedPlanName!),
        FillGrid(
          // Three across on the kiosk stage, degrading to two on a narrower
          // fold — the class grid's own numbers.
          minItemWidth: 300,
          minColumns: 2,
          children: [
            for (final plan in state.plans)
              _PlanTile(
                state: state,
                plan: plan,
                selected: plan.planId == picked,
                onPick: onPick,
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

/// One plan card, carrying whichever block reason closes it for the person
/// currently picking (the rules live in `kiosk_plan_block.dart`).
///
/// The reason drives BOTH the tag and — through the cubit's tap branch — the
/// popup behind it, from the one copy file, so a card can never wear a tag that
/// disagrees with the answer the tap gives.
class _PlanTile extends StatelessWidget {
  final KioskSignupState state;
  final MembershipPlanResponse plan;
  final bool selected;
  final ValueChanged<String> onPick;

  const _PlanTile({
    required this.state,
    required this.plan,
    required this.selected,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final reason = state.planBlockReason(plan);
    return FlowPlanCard(
      plan: plan,
      selected: selected,
      // A blocked plan can never be selected; the cubit turns its tap into the
      // explanation instead.
      blocked: reason != null,
      blockedLabel: reason == null
          ? 'Already used'
          : kioskPlanBlockTag(reason),
      onTap: () => onPick(plan.planId),
    );
  }
}
