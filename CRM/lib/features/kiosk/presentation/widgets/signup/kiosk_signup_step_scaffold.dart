import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_state.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_stage.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_flow_rail.dart';

/// Every signup step wears the same three bands: the step rail, the screen
/// head (one title + one answering line), and the step's own content — over
/// the footer `KioskStage` pins to the fold.
///
/// It exists so no step re-derives its own chrome. A step that laid out its
/// own rail would be one refactor away from disagreeing with its neighbours
/// about which rung is lit, and a member watching the rail jump around loses
/// the one thing it is for.
class KioskSignupStepScaffold extends StatelessWidget {
  /// Which step this is — the rail lights the matching rung.
  final KioskSignupStep step;

  final String title;

  /// The one line under the title. It answers the question the member
  /// actually has in front of this screen; it never apologises and never
  /// sells.
  final String? subtitle;

  /// The step's body — usually a `KioskSignupFormPanel`.
  final Widget child;

  /// The pinned `KioskFlowFoot`.
  final Widget foot;

  const KioskSignupStepScaffold({
    super.key,
    required this.step,
    required this.title,
    required this.child,
    required this.foot,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return KioskStage(
      footer: foot,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: DesignConstants.spacingBig,
        children: [
          const _Rail(),
          _Head(title: title, subtitle: subtitle),
          child,
        ],
      ),
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
          child: KioskFlowRail(
            steps: group ? kKioskGroupFlowSteps : kKioskSoloFlowSteps,
            current: kioskFlowRailIndex(state.step, isGroup: group),
          ),
        );
      },
    );
  }
}

/// Which rung of the rail a [KioskSignupStep] lights.
///
/// The two templates differ by ONE rung (ruling 8): the solo rail has no
/// "People" of its own, so the roster steps light the rung the member is
/// heading INTO (Plan) rather than one they have already finished — a rail
/// must never sit on a completed step.
int kioskFlowRailIndex(KioskSignupStep step, {required bool isGroup}) {
  return switch (step) {
    KioskSignupStep.details => 0,
    KioskSignupStep.extraDetails => 1,
    KioskSignupStep.people ||
    KioskSignupStep.personDetails ||
    KioskSignupStep.match =>
      2,
    KioskSignupStep.plans => isGroup ? 3 : 2,
    KioskSignupStep.waivers => isGroup ? 4 : 3,
    KioskSignupStep.card => isGroup ? 5 : 4,
    // Review / Paying / Declined / Welcome all belong to the final "Pay"
    // rung: they are one act from the member's side, and the rail must not
    // imply a step exists between reviewing and paying.
    KioskSignupStep.review ||
    KioskSignupStep.paying ||
    KioskSignupStep.declined ||
    KioskSignupStep.welcome =>
      isGroup ? 6 : 5,
    // The stop screen renders no rail at all (a terminal is not a step), so
    // this value is never drawn; it stays in range rather than throwing.
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
    final line = subtitle;
    return Column(
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingMedium,
      children: [
        Text(
          title,
          style: DesignConstants.kioskDisplay,
          textAlign: TextAlign.center,
        ),
        if (line != null)
          Text(
            line,
            style: DesignConstants.kioskSubtitle.copyWith(
              color: DesignConstants.text2nd,
            ),
            textAlign: TextAlign.center,
          ),
      ],
    );
  }
}
