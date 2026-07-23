import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/shared/widgets/app_spinner.dart';

/// The full-screen "checking you in" beat — the shared [AppSpinner] over a
/// kiosk-scale caption, so a member reading from across the room knows their
/// tap registered while the `is_member: true` check-in request is in flight
/// (a bare spinner reads as "stuck").
class KioskCheckingIn extends StatelessWidget {
  const KioskCheckingIn({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DesignConstants.paddingBig),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: DesignConstants.spacingLarge,
          children: [
            const AppSpinner(),
            Text(
              'Checking you in…',
              style: DesignConstants.h2.copyWith(
                color: DesignConstants.text2nd,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
