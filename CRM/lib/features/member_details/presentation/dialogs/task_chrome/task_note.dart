import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/membership_flow/config/membership_flow_theme.dart';

/// The quiet line a nested staff dialog uses for the fact that is true but is
/// not the decision — what is optional, what will never appear in a list, what
/// this surface deliberately cannot do.
///
/// It is the flow's own supporting role rather than a size of its own, so it
/// stays a step under everything it sits beneath and can never out-shout the
/// control it explains.
class TaskNote extends StatelessWidget {
  final String message;
  final TextAlign? textAlign;

  const TaskNote(this.message, {super.key, this.textAlign});

  @override
  Widget build(BuildContext context) {
    final scale = MembershipFlowTheme.of(context);
    return Text(
      message,
      style: scale.caption.copyWith(color: DesignConstants.text2nd),
      textAlign: textAlign,
    );
  }
}
