import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/membership_flow/config/membership_flow_theme.dart';
import 'package:crm/features/membership_flow/presentation/chrome/flow_rail.dart';
import 'package:crm/features/membership_flow/presentation/chrome/flow_shell.dart';

/// Every purchase step wears the same bands: the step rail, the screen head
/// (one title + one answering line), an optional "who is this for" strip, and
/// the step's own content.
///
/// It exists so no step re-derives its own chrome — a step laying out its own
/// rail is one refactor away from disagreeing with its neighbours about which
/// rung is lit.
///
/// The whole top band is PINNED: rail, title and identity stay on the fold
/// while the content scrolls beneath them. That is a correctness control on the
/// plan, waiver and card steps, not decoration — the cost of losing it is the
/// wrong plan bought for the wrong child, or a card on the wrong profile. The
/// scaffold only ASSEMBLES those bands; [shell] is the host's, and holding them
/// on the fold is the shell's side of the contract.
class FlowStepScaffold extends StatelessWidget {
  /// The rail's template — the step labels this surface walks. Passed rather
  /// than derived so one scaffold serves both templates and both surfaces.
  final List<String> railSteps;

  /// Which rung of [railSteps] is lit. The host owns the mapping, because it
  /// is the host's own step spine being mapped.
  final int railIndex;

  final String title;

  /// The one line under the title — it answers the question the member
  /// actually has in front of this screen, and never sells.
  final String? subtitle;

  /// The pinned `FlowWhoFor` strip, on the steps that are ABOUT one person.
  /// Null on the steps that are about the purchase as a whole.
  final Widget? identity;

  /// The step's body — usually a `FlowFormPanel`.
  final Widget child;

  /// The pinned `FlowFoot`.
  final Widget foot;

  /// See [FlowShellParts.fillBody]. The waiver steps opt in so their reading
  /// box can fill the fold and scroll inside itself.
  final bool fillBody;

  /// See [FlowShellParts.bodyController].
  final ScrollController? bodyController;

  /// The HOST's shell — a full-screen kiosk stage, or the desk's dialog body.
  /// It receives the assembled bands and decides what holds them.
  final FlowShellBuilder shell;

  const FlowStepScaffold({
    super.key,
    required this.railSteps,
    required this.railIndex,
    required this.title,
    required this.child,
    required this.foot,
    required this.shell,
    this.subtitle,
    this.identity,
    this.fillBody = false,
    this.bodyController,
  });

  @override
  Widget build(BuildContext context) {
    return shell(
      context,
      FlowShellParts(
        fillBody: fillBody,
        bodyController: bodyController,
        footer: foot,
        body: child,
        header: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          spacing: DesignConstants.spacingLarge,
          children: [
            Center(child: FlowRail(steps: railSteps, current: railIndex)),
            _Head(title: title, subtitle: subtitle),
            ?identity,
          ],
        ),
      ),
    );
  }
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
