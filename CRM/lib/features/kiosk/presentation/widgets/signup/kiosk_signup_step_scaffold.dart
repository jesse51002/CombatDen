import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_state.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_stage.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_flow_rail.dart';

/// Every signup step wears the same bands: the step rail, the screen head (one
/// title + one answering line), an optional "who is this for" strip, and the
/// step's own content — between the header and footer `KioskStage` pins to the
/// fold.
///
/// It exists so no step re-derives its own chrome. A step that laid out its
/// own rail would be one refactor away from disagreeing with its neighbours
/// about which rung is lit, and a member watching the rail jump around loses
/// the one thing it is for.
///
/// **The whole top band is PINNED.** Rail, title and identity stay on the fold
/// while the content scrolls beneath them, so the answer to "who am I doing
/// this for" is on screen for the entire step rather than for as long as
/// nobody scrolls. That is a correctness control on the plan, waiver and card
/// steps, not decoration — the cost of losing it is the wrong plan bought for
/// the wrong child, or a card attached to the wrong profile.
class KioskSignupStepScaffold extends StatelessWidget {
  /// Which step this is — the rail lights the matching rung.
  final KioskSignupStep step;

  final String title;

  /// The one line under the title. It answers the question the member
  /// actually has in front of this screen; it never apologises and never
  /// sells.
  final String? subtitle;

  /// The pinned `KioskWhoFor` strip, on the steps that are ABOUT one person.
  /// Null on the steps that are about the signup as a whole.
  final Widget? identity;

  /// The step's body — usually a `KioskSignupFormPanel`.
  final Widget child;

  /// The pinned `KioskFlowFoot`.
  final Widget foot;

  /// Hand [child] the height that is LEFT instead of scrolling it — see
  /// [KioskStage.fillBody]. The waiver steps opt in so their reading box can
  /// fill the fold and scroll inside itself.
  final bool fillBody;

  /// Drives the scrolling body, so a step can return it to the top — the plan
  /// step uses it to scroll back up after a plan is picked (and when the group
  /// advances to the next person). See [KioskStage.bodyScrollController].
  final ScrollController? bodyController;

  const KioskSignupStepScaffold({
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
    return KioskStage(
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
    // The payer match is still about WHO this person is, so it belongs to the
    // rung they are standing on rather than advertising progress they have
    // not made.
    KioskSignupStep.extraDetails || KioskSignupStep.payerMatch => 1,
    KioskSignupStep.people ||
    KioskSignupStep.personDetails ||
    KioskSignupStep.match ||
    KioskSignupStep.payerPick =>
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
