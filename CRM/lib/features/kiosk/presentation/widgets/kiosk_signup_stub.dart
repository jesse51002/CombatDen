import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';

/// The signup entry point is a Phase D flow. Until it lands, the kiosk's
/// "New here? Sign up" button opens this calm front-desk handoff — a clearly
/// temporary placeholder, NOT the signup flow.
Future<void> showKioskSignupStub(BuildContext context) {
  return AppDialog.show<void>(
    context: context,
    title: 'New here?',
    body: Text(
      'To sign up, please see the front desk — a coach will get you set up.',
      style: DesignConstants.pBig.copyWith(color: DesignConstants.text2nd),
    ),
    primaryLabel: 'Okay',
    primaryOnPressed: (dialogContext) => Navigator.of(dialogContext).pop(),
    // Single-action info modal — no secondary "Cancel".
    secondaryLabel: null,
  );
}
