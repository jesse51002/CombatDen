import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/presentation/dialogs/task_chrome/task_panel.dart';
import 'package:crm/features/membership_flow/config/membership_flow_theme.dart';

/// The visible end of a nested staff dialog's task: a glyph carrying the
/// outcome's colour, and one sentence naming what happened.
///
/// Every mutation these dialogs run lands here and waits to be dismissed —
/// never a spinner that disappears. The COLOUR lives on the glyph and the
/// sentence stays in ink, so a failure reads as a fact rather than as shouting.
///
/// It brings its own [TaskPanel]: an outcome is the whole of what is on screen
/// when it shows, so there is never a second thing for it to sit beside.
class TaskTerminal extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String message;

  const TaskTerminal({
    super.key,
    required this.icon,
    required this.color,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final scale = MembershipFlowTheme.of(context);
    return TaskPanel(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          spacing: DesignConstants.spacingLarge,
          children: [
            Icon(
              icon,
              size: DesignConstants.iconSizeBig,
              weight: DesignConstants.iconWeight,
              color: color,
            ),
            Text(
              message,
              style: scale.body.copyWith(color: DesignConstants.text),
            ),
          ],
        ),
      ],
    );
  }
}
