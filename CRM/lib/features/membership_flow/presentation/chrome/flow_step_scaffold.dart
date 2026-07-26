import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_state.dart';
import 'package:crm/features/membership_flow/config/membership_flow_theme.dart';
import 'package:crm/features/membership_flow/presentation/chrome/flow_rail.dart';
import 'package:crm/features/membership_flow/presentation/chrome/flow_stage.dart';

/// Every signup step wears the same bands: the step rail, the screen head (one
/// title + one answering line), an optional "who is this for" strip, and the
/// step's own content.
///
/// It exists so no step re-derives its own chrome — a step laying out its own
/// rail is one refactor away from disagreeing with its neighbours about which
/// rung is lit.
///
/// The whole top band is PINNED: rail, title and identity stay on the fold
/// while the content scrolls beneath them. That is a correctness control on the
/// plan, waiver and card steps, not decoration — the cost of losing it is the
/// wrong plan bought for the wrong child, or a card on the wrong profile.
class FlowStepScaffold extends StatelessWidget {
  /// Which step this is — the rail lights the matching rung.
  final KioskSignupStep step;

  final String title;

  /// The one line under the title — it answers the question the member
  /// actually has in front of this screen, and never sells.
  final String? subtitle;

  /// The pinned `FlowWhoFor` strip, on the steps that are ABOUT one person.
  /// Null on the steps that are about the signup as a whole.
  final Widget? identity;

  /// The step's body — usually a `FlowFormPanel`.
  final Widget child;

  /// The pinned `FlowFoot`.
  final Widget foot;

  /// Hand [child] the height that is LEFT instead of scrolling it — see
  /// [FlowStage.fillBody]. The waiver steps opt in so their reading box can
  /// fill the fold and scroll inside itself.
  final bool fillBody;

  /// Drives the scrolling body so a step can return it to the top — the plan
  /// step scrolls back up after a pick. See [FlowStage.bodyScrollController].
  final ScrollController? bodyController;

  const FlowStepScaffold({
    super.key,
    required this.step,
    required this.title,
    required this.child,
    required this.foot,
    this.subtitle,
    this.identity,
    this.fillBody = false,
    this.bodyController,
  });

  @override
  Widget build(BuildContext context) {
    return FlowStage(
      footer: foot,
      fillBody: fillBody,
      bodyScrollController: bodyController,
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: DesignConstants.spacingLarge,
        children: [
          const _Rail(),
          _Head(title: title, subtitle: subtitle),
          ?identity,
        ],
      ),
      child: child,
    );
  }
}

/// The rail, reading its template + rung straight off the cubit so a step
/// never passes them by hand.
class _Rail extends StatelessWidget {
  const _Rail();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<KioskSignupCubit, KioskSignupState>(
      buildWhen: (prev, cur) =>
          prev.step != cur.step || prev.isGroup != cur.isGroup,
      builder: (context, state) {
        final group = state.isGroup;
        return Center(
          child: FlowRail(
            steps: group ? kFlowGroupSteps : kFlowSoloSteps,
            current: flowRailIndex(state.step, isGroup: group),
          ),
        );
      },
    );
  }
}

/// Which rung of the rail a [KioskSignupStep] lights.
///
/// The two templates differ by ONE rung (ruling 8): the solo rail has no
/// "People" of its own, so its roster steps light the rung the member is
/// heading INTO rather than one already finished — a rail must never sit on a
/// completed step.
///
/// The templates are fixed at 6 solo / 7 group and no step adds a rung: a step
/// still about WHO this person is (the entry fork, the identify search, the
/// payer match) shares the rung they are standing on rather than advertising
/// progress they have not made.
int flowRailIndex(KioskSignupStep step, {required bool isGroup}) {
  return switch (step) {
    KioskSignupStep.entry ||
    KioskSignupStep.identify ||
    KioskSignupStep.details =>
      0,
    KioskSignupStep.extraDetails || KioskSignupStep.payerMatch => 1,
    KioskSignupStep.people ||
    KioskSignupStep.personDetails ||
    KioskSignupStep.match ||
    KioskSignupStep.payerPick =>
      2,
    KioskSignupStep.plans => isGroup ? 3 : 2,
    KioskSignupStep.waivers => isGroup ? 4 : 3,
    KioskSignupStep.card => isGroup ? 5 : 4,
    // Review / Paying / Results / Declined / Welcome are ONE act from the
    // member's side, so they share the final "Pay" rung: the rail must not
    // imply a step exists between reviewing and paying.
    KioskSignupStep.review ||
    KioskSignupStep.paying ||
    KioskSignupStep.results ||
    KioskSignupStep.declined ||
    KioskSignupStep.welcome =>
      isGroup ? 6 : 5,
    // The stop screen draws no rail (a terminal is not a step), so this value
    // is never used; it stays in range rather than throwing.
    KioskSignupStep.stop => 0,
  };
}

/// The screen head: one title, and at most one line answering it.
class _Head extends StatelessWidget {
  final String title;
  final String? subtitle;

  const _Head({required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    final scale = MembershipFlowTheme.of(context);
    final line = subtitle;
    return Column(
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingMedium,
      children: [
        Text(
          title,
          style: scale.display,
          textAlign: TextAlign.center,
        ),
        if (line != null)
          Text(
            line,
            style: scale.subtitle.copyWith(
              color: DesignConstants.text2nd,
            ),
            textAlign: TextAlign.center,
          ),
      ],
    );
  }
}
