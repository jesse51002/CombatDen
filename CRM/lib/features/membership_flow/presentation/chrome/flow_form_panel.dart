import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/membership_flow/config/membership_flow_theme.dart';

/// The white lifted panel a signup step's fields sit on — the same object card
/// the rest of the app uses, capped at a readable measure and centred on the
/// wide kiosk stage.
///
/// One panel per step. A step that needs internal grouping uses
/// [FlowDetailGroup] inside it — two panels read as two unrelated forms.
class FlowFormPanel extends StatelessWidget {
  final List<Widget> children;

  const FlowFormPanel({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    final scale = MembershipFlowTheme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: scale.formMeasure),
        child: Container(
          padding: const EdgeInsets.all(DesignConstants.paddingBig),
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
        ),
      ),
    );
  }
}
