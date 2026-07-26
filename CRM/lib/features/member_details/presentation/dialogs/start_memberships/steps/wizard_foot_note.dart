import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/membership_flow/config/membership_flow_theme.dart';

/// The line a step puts directly ABOVE its footer band, naming why the
/// primary is unavailable and which control clears it.
///
/// It rides above `FlowFoot`'s own hairline rather than under the body, so it
/// reads as part of the decision band: a disabled button whose reason sits at
/// the bottom of a scrolling body is a button with no reason at all.
class WizardFootNote extends StatelessWidget {
  final String text;

  const WizardFootNote({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    final scale = MembershipFlowTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: DesignConstants.spacingSmall),
      child: Text(
        text,
        style: scale.caption.copyWith(color: DesignConstants.text2nd),
        textAlign: TextAlign.center,
      ),
    );
  }
}
