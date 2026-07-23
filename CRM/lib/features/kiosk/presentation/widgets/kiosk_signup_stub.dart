import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';

/// The signup entry point is a Phase D flow. Until it lands, the kiosk's
/// "New here? Sign up" button opens this calm front-desk handoff — a clearly
/// temporary placeholder, NOT the signup flow.
///
/// **This dialog deliberately stays on the shared `AppDialog` scale**, body
/// included (`pBig`), rather than reaching for a kiosk-ramp token. `AppDialog`
/// owns its own internally-proportional ladder — title `h1` 24 > body
/// `pBig` 16 > `AppDialogActions`' 13px buttons — and putting *only* the body
/// on the kiosk ramp would desync it from the title and buttons above and
/// below it the next time the kiosk ramp moves: the exact half-scaled surface
/// the kiosk ramp exists to prevent. A kiosk-scale dialog shell is a separate
/// call (it would mean a `kiosk` opt-in through `AppDialog` /
/// `AppDialogTitle` / `AppDialogActions`), not something to half-do here.
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
