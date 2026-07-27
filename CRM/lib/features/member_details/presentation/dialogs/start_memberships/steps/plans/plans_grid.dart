import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_derived.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_state.dart';
import 'package:crm/features/member_details/data/models/membership_plan_response.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/wizard_copy.dart';
import 'package:crm/features/membership_flow/config/membership_flow_theme.dart';
import 'package:crm/features/membership_flow/presentation/widgets/flow_inline_notice.dart';
import 'package:crm/features/membership_flow/presentation/widgets/flow_plan_card.dart';
import 'package:crm/shared/widgets/fill_grid.dart';

/// AVAILABLE PLANS — the gym's sellable catalogue for the person on screen.
///
/// A gated plan is BLOCKED, never hidden: dimmed, tagged with the gate's own
/// reason, and still tappable, so the tap opens the answer instead of a
/// greyed-out dead end. The tag rides `FlowPlanCard`'s warm scrim treatment
/// and no colour is added here — a "you cannot sell this" painted in the
/// success green is what this screen exists to stop.
class PlansGrid extends StatelessWidget {
  final MembershipWizardState state;
  final String memberId;

  /// The blocked reason currently on screen, already worded by the step.
  final String? blockedNote;

  final ValueChanged<MembershipPlanResponse> onPick;
  final ValueChanged<MembershipPlanResponse> onBlocked;

  const PlansGrid({
    super.key,
    required this.state,
    required this.memberId,
    required this.blockedNote,
    required this.onPick,
    required this.onBlocked,
  });

  @override
  Widget build(BuildContext context) {
    final scale = MembershipFlowTheme.of(context);
    final note = blockedNote;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingLarge,
      children: [
        Text(WizardPlansCopy.availableEyebrow, style: scale.eyebrow),
        if (note != null) FlowInlineNotice(message: note),
        FillGrid(
          // Three across at the desk's form measure, degrading to two on a
          // narrower fold — the same numbers the class grid uses.
          minItemWidth: 260,
          minColumns: 2,
          children: [
            for (final plan in state.plans)
              _Cell(
                state: state,
                memberId: memberId,
                plan: plan,
                onPick: onPick,
                onBlocked: onBlocked,
              ),
          ],
        ),
        const _Notes(),
      ],
    );
  }
}

/// One plan, over whatever advisories apply to it.
///
/// A NOTE is not a block — a repeat trial is exactly what staff grant at a
/// desk — so it renders as a quiet line under the card and never closes it.
class _Cell extends StatelessWidget {
  final MembershipWizardState state;
  final String memberId;
  final MembershipPlanResponse plan;
  final ValueChanged<MembershipPlanResponse> onPick;
  final ValueChanged<MembershipPlanResponse> onBlocked;

  const _Cell({
    required this.state,
    required this.memberId,
    required this.plan,
    required this.onPick,
    required this.onBlocked,
  });

  @override
  Widget build(BuildContext context) {
    final scale = MembershipFlowTheme.of(context);
    final gate = state.gateFor(memberId, plan);
    final selected = state
        .draftsFor(memberId)
        .any((draft) => draft.plan.planId == plan.planId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingSmall,
      children: [
        FlowPlanCard(
          plan: plan,
          selected: selected,
          blocked: gate != null,
          blockedLabel: gate?.reason,
          onTap: () {
            if (gate == null) {
              onPick(plan);
              return;
            }
            onBlocked(plan);
          },
        ),
        for (final note in state.notesFor(memberId, plan))
          Text(
            note.note,
            style: scale.caption.copyWith(color: DesignConstants.text2nd),
          ),
      ],
    );
  }
}

/// The two honesty lines under the grid: which figure is authoritative, and
/// why a plan the gym has might not be listed at all.
class _Notes extends StatelessWidget {
  const _Notes();

  @override
  Widget build(BuildContext context) {
    final scale = MembershipFlowTheme.of(context);
    final style = scale.caption.copyWith(color: DesignConstants.text2nd);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingSmall,
      children: [
        Text(WizardPlansCopy.estimateNote, style: style),
        Text(WizardPlansCopy.unpricedNote, style: style),
      ],
    );
  }
}
