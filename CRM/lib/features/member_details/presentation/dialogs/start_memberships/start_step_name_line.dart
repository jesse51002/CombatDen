import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';

/// The plain-language step-name line rendered under the wizard's group
/// indicator — e.g. `Pick plans · Step 4 of 9`. Shared by the start-memberships
/// step body and the add-member flow chrome so both read identically.
class StartStepNameLine extends StatelessWidget {
  final String text;

  const StartStepNameLine({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: DesignConstants.pSmall.copyWith(
        color: DesignConstants.text2nd,
      ),
    );
  }
}
