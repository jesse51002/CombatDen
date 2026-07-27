import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/membership_flow/config/membership_flow_theme.dart';

/// A field's label, and the one place the muted word beside it may sit — who
/// handles the value ("Handled by Stripe"), or that it is optional.
///
/// It exists for the fields a dialog does NOT own: a Stripe card field brings
/// its own box and no label at all, so the label above it has to be composed
/// rather than passed. `FlowFieldBox` renders the same pair for every field it
/// does own.
class TaskFieldLabel extends StatelessWidget {
  final String label;

  /// The muted word beside [label].
  final String? note;

  const TaskFieldLabel({super.key, required this.label, this.note});

  @override
  Widget build(BuildContext context) {
    final scale = MembershipFlowTheme.of(context);
    final word = note;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      spacing: DesignConstants.spacingMedium,
      children: [
        Flexible(child: Text(label, style: scale.label)),
        if (word != null)
          Text(
            word,
            style: scale.caption.copyWith(
              color: DesignConstants.text2nd,
            ),
          ),
      ],
    );
  }
}
