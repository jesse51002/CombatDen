import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/membership_flow/config/membership_flow_theme.dart';

/// What a pill MEANS, which is the only thing that decides its colour.
///
/// [warm] is the flow's failure/attention reading — `yellowDark` on
/// `okYellow`, never red: everything a desk pill marks here is recoverable,
/// and red is reserved for a hard validation error.
enum WizardPillTone { quiet, good, loud, warm }

/// A short status mark pinned to the end of a row — "Signed", "Signing now",
/// "Not usable for this run".
///
/// Desk-only, so it lives here rather than under `membership_flow/`: the kiosk
/// never shows a waiver run or a blocked card. Its type comes from the flow
/// SCALE like every other word in the run, so it cannot drift out of step with
/// the rows it sits on.
class WizardPill extends StatelessWidget {
  final String label;
  final WizardPillTone tone;

  const WizardPill({
    super.key,
    required this.label,
    this.tone = WizardPillTone.quiet,
  });

  @override
  Widget build(BuildContext context) {
    final scale = MembershipFlowTheme.of(context);
    final fill = switch (tone) {
      WizardPillTone.quiet => DesignConstants.surface,
      WizardPillTone.good => DesignConstants.greenDark,
      WizardPillTone.loud => DesignConstants.primaryColor,
      WizardPillTone.warm => DesignConstants.yellowDark,
    };
    final ink = switch (tone) {
      WizardPillTone.quiet => DesignConstants.text2nd,
      WizardPillTone.good => DesignConstants.goodGreen,
      WizardPillTone.loud => DesignConstants.onAccent,
      WizardPillTone.warm => DesignConstants.okYellow,
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignConstants.spacingMedium,
        vertical: DesignConstants.spacingSmall,
      ),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
        // Only the quiet tone is outlined: a toned fill already separates
        // itself from the panel, and a border on top reads as a second box.
        border: tone == WizardPillTone.quiet
            ? Border.all(color: DesignConstants.line)
            : null,
      ),
      child: Text(label, style: scale.micro.copyWith(color: ink)),
    );
  }
}
