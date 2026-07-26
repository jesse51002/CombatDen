import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';

/// The white lifted object card the desk's steps group content on — the same
/// recipe `FlowFormPanel`, `FlowSignPanel`, `FlowMoneyPanel` and
/// `FlowReviewGroupPanel` all wear.
///
/// It exists next to `FlowFormPanel` rather than instead of it because that
/// one CENTRES itself and caps its own width at the surface's form measure,
/// which is right for a single-column step and wrong inside a two-up: a panel
/// that re-caps its width inside a half-width column leaves the column half
/// empty. This is the same card with the sizing left to its parent.
class WizardPanel extends StatelessWidget {
  final List<Widget> children;

  const WizardPanel({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(DesignConstants.paddingSmall),
      decoration: BoxDecoration(
        color: DesignConstants.surface,
        borderRadius: BorderRadius.circular(DesignConstants.radiusCard),
        border: Border.all(color: DesignConstants.line),
        boxShadow: DesignConstants.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: DesignConstants.spacingLarge,
        children: children,
      ),
    );
  }
}
