import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';

/// The Incomplete view's row action — opens this member's detail page,
/// where the start-membership wizard finishes what the signup started.
///
/// The whole row already routes to the same place; the explicit button
/// is what makes the list read as a work queue rather than a report, and
/// it is the affordance staff reach for when the person is standing at
/// the desk asking why the kiosk says they already have an account.
///
/// Styling matches the waivers section's row-level "Sign" button — the
/// app's established in-table action.
class FinishSignupCell extends StatelessWidget {
  final VoidCallback onPressed;

  const FinishSignupCell({
    super.key,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: AppOutlineButton(
        text: 'Finish signup',
        borderRadius: DesignConstants.radiusSmall,
        textStyle: DesignConstants.pSmall,
        padding: const EdgeInsets.symmetric(
          horizontal: DesignConstants.spacingMedium,
          vertical: DesignConstants.spacingTiny,
        ),
        onPressed: onPressed,
      ),
    );
  }
}
