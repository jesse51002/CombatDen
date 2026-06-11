import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/shared/widgets/app_spinner.dart';

/// The results step's in-flight state: a centered spinner
/// while the start POST is processing.
class StartResultsProcessing extends StatelessWidget {
  const StartResultsProcessing({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 160,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: DesignConstants.spacingMedium,
          children: [
            const AppSpinner(),
            Text(
              'Starting memberships…',
              style: DesignConstants.p.copyWith(
                color: DesignConstants.text2nd,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
