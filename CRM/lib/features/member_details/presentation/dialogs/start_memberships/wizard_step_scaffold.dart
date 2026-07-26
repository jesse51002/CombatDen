import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_step.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/wizard_rail.dart';
import 'package:crm/features/membership_flow/presentation/chrome/flow_shell.dart';
import 'package:crm/features/membership_flow/presentation/chrome/flow_step_scaffold.dart';

/// The desk's binding of the shared [FlowStepScaffold] — the per-SURFACE half
/// of the wizard chrome, and the only place the desk names either.
///
/// Two things are bound here, and both are the host's by definition:
/// - the SHELL is the dialog body: a pinned head, a body that scrolls inside
///   the fixed viewport fraction, and a pinned foot. The kiosk binds the same
///   scaffold to its full-screen stage instead;
/// - the RAIL is the desk's six named stages, mapped from the cubit's step,
///   so no step passes its template or its rung by hand.
class WizardStepScaffold extends StatelessWidget {
  /// Which step this is — the rail lights the matching rung.
  final MembershipWizardStep step;

  /// Whether the run still owes a signature, which decides the waivers rung.
  final bool hasWaivers;

  /// The always-done leading rung, when this run is the add-member tail.
  final bool showAddMemberGroup;

  final String title;
  final String? subtitle;

  /// The pinned identity strip, on the steps that are ABOUT one person.
  final Widget? identity;

  final Widget child;
  final Widget foot;

  /// See [FlowShellParts.fillBody] — the waiver step opts in so its reading
  /// box can fill the fold and scroll inside itself.
  final bool fillBody;

  /// See [FlowShellParts.bodyController].
  final ScrollController? bodyController;

  const WizardStepScaffold({
    super.key,
    required this.step,
    required this.hasWaivers,
    required this.showAddMemberGroup,
    required this.title,
    required this.child,
    required this.foot,
    this.subtitle,
    this.identity,
    this.fillBody = false,
    this.bodyController,
  });

  /// The desk's shell. A `static` function rather than a closure so every step
  /// hands the scaffold the same object and none can quietly wrap it.
  static Widget _stage(BuildContext context, FlowShellParts parts) {
    final body = parts.fillBody
        ? parts.body
        : SingleChildScrollView(
            controller: parts.bodyController,
            child: parts.body,
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      // Body to foot is the TIGHT gap: the foot is the answer to what is on
      // screen. Head to body is the wide one, nested below.
      spacing: DesignConstants.spacingMedium,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: DesignConstants.spacingBig,
            children: [
              parts.header,
              Expanded(child: body),
            ],
          ),
        ),
        parts.footer,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return FlowStepScaffold(
      railSteps: wizardRailSteps(
        hasWaivers: hasWaivers,
        showAddMemberGroup: showAddMemberGroup,
      ),
      railIndex: wizardRailIndex(
        step,
        hasWaivers: hasWaivers,
        showAddMemberGroup: showAddMemberGroup,
      ),
      title: title,
      subtitle: subtitle,
      identity: identity,
      fillBody: fillBody,
      bodyController: bodyController,
      foot: foot,
      shell: _stage,
      child: child,
    );
  }
}
