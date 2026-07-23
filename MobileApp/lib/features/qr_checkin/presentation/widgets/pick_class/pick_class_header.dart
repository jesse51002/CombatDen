import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/shared/widgets/buttons/app_close_button.dart';

/// Header for the pick-class step: a close affordance (exits the check-in flow
/// back to home) above the prompt asking which class the member is here for.
class PickClassHeader extends StatelessWidget {
  const PickClassHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: DesignConstants.spacingSmall,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: DesignConstants.spacingMedium,
        children: [
          const Align(
            alignment: Alignment.centerLeft,
            child: AppCloseButton(),
          ),
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: DesignConstants.spacingMedium,
            ),
            child: Text(
              "Which class are you checking into?",
              style: DesignConstants.h1,
            ),
          ),
        ],
      ),
    );
  }
}
