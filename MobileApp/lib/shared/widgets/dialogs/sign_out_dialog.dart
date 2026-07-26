import 'package:flutter/material.dart';

import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/shared/widgets/buttons/app_outline_button.dart';
import 'package:mobile_app/shared/widgets/buttons/app_primary_button.dart';

/// Confirmation for the profile screen's account-level "Sign out".
///
/// The SAFE action gets the primary treatment — signing out is the rare,
/// deliberate one, so it's the outlined destructive button underneath.
/// Confirming pops `true`; dismissing pops `false` / null. The caller (which
/// holds the [LoginBloc]) dispatches the sign-out.
class SignOutDialog extends StatelessWidget {
  const SignOutDialog({super.key});

  /// Open the dialog; resolves to `true` when the member confirms.
  static Future<bool?> show(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (_) => const SignOutDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: DesignConstants.popup,
      insetPadding: EdgeInsets.symmetric(
        horizontal: DesignConstants.spacingBig,
        vertical: DesignConstants.spacingBig,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
      ),
      child: Padding(
        padding: EdgeInsets.all(DesignConstants.paddingSmall),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: DesignConstants.spacingLarge,
          children: [
            Text(
              'Sign out?',
              style: DesignConstants.h1,
              textAlign: TextAlign.center,
            ),
            Text(
              "You'll sign back in with your email. Your streak, points and "
              'rank stay on your account.',
              style: DesignConstants.p.copyWith(
                color: DesignConstants.text2nd,
              ),
              textAlign: TextAlign.center,
            ),
            AppPrimaryButton(
              text: 'Stay signed in',
              fullWidth: true,
              onPressed: () => Navigator.of(context).pop(false),
            ),
            AppOutlineButton(
              text: 'Sign out',
              fullWidth: true,
              borderRadius: DesignConstants.radiusSmall,
              borderColor: DesignConstants.badRed,
              textColor: DesignConstants.badRed,
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        ),
      ),
    );
  }
}
