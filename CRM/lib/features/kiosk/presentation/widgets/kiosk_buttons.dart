import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';
import 'package:crm/shared/widgets/app_primary_button.dart';

/// The kiosk's two buttons — the shared [AppPrimaryButton] / [AppOutlineButton]
/// wearing the kiosk display scale instead of the admin defaults.
///
/// The kiosk is read and pressed from standing distance, so its labels and hit
/// boxes run a step larger (mockup `.btn-primary` 19px / 18x34,
/// `.btn-outline` 17px / 15x30) than the 13px / 16x8 admin buttons. These two
/// wrappers are the ONLY place those tokens are applied: every kiosk button
/// goes through them, so the whole set scales together and can never desync,
/// and no kiosk call site ever restates a size. The admin surfaces keep the
/// base buttons untouched.

/// The kiosk's primary action — the brand gradient CTA at kiosk scale.
class KioskPrimaryButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;

  const KioskPrimaryButton({
    super.key,
    required this.text,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return AppPrimaryButton(
      text: text,
      onPressed: onPressed,
      textStyle: DesignConstants.kioskButtonPrimaryLabel,
      padding: DesignConstants.kioskButtonPrimaryPadding,
    );
  }
}

/// The kiosk's secondary action (Done / Okay / Sign up) — the ink-outlined
/// button at kiosk scale.
class KioskOutlineButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;

  const KioskOutlineButton({
    super.key,
    required this.text,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return AppOutlineButton(
      text: text,
      onPressed: onPressed,
      textStyle: DesignConstants.kioskButtonOutlineLabel,
      padding: DesignConstants.kioskButtonOutlinePadding,
    );
  }
}
