import 'package:flutter/material.dart';

import 'package:crm/features/member_details/presentation/dialogs/start_memberships/steps/wizard_foot_note.dart';
import 'package:crm/features/membership_flow/presentation/chrome/flow_foot.dart';

/// The desk's footer: the shared [FlowFoot] with the one thing the desk adds
/// above it — a [WizardFootNote] saying WHY the primary is closed.
///
/// The roster and plans steps assemble the same pair by hand inside their own
/// step-specific feet, which carry decision logic of their own; the four steps
/// after them need only the pair, so they take it from here rather than each
/// restating the Column. Every word arrives from the step's copy; this widget
/// names none.
class WizardStepFoot extends StatelessWidget {
  /// The line above the hairline. Null on a step with nothing to explain.
  final String? note;

  /// Null on the terminal screens, where leaving would strand a charge.
  final VoidCallback? onEscape;
  final String? escapeLabel;
  final VoidCallback? onBack;
  final VoidCallback? onPrimary;
  final String? primaryLabel;
  final VoidCallback? onSkip;
  final String? skipLabel;

  const WizardStepFoot({
    super.key,
    required this.onEscape,
    this.note,
    this.escapeLabel,
    this.onBack,
    this.onPrimary,
    this.primaryLabel,
    this.onSkip,
    this.skipLabel,
  });

  @override
  Widget build(BuildContext context) {
    final line = note;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (line != null) WizardFootNote(text: line),
        FlowFoot(
          onPrimary: onPrimary,
          primaryLabel: primaryLabel,
          onBack: onBack,
          onSkip: onSkip,
          skipLabel: skipLabel,
          onEscape: onEscape,
          escapeLabel: escapeLabel,
        ),
      ],
    );
  }
}
