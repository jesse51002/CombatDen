import 'package:flutter/material.dart';
import 'package:mobile_app/core/constants/design_constants.dart';
import 'package:mobile_app/core/navigation/app_routes.dart';
import 'package:mobile_app/shared/widgets/buttons/app_primary_button.dart';
import 'package:mobile_app/shared/widgets/scaffold/app_screen_scaffold.dart';

/// Confirmation screen shown after a successful class reservation.
///
/// Mirrors Figma `ReservingLoading` (formerly used for a 2s loading state,
/// now repurposed as a booked-confirmation moment). The user advances by
/// pressing the Continue button — there is no auto-redirect.
class ClassBookedScreen extends StatelessWidget {
  const ClassBookedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScreenScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Expanded(child: _CelebrationContent()),
          Padding(
            padding: EdgeInsets.only(bottom: DesignConstants.spacingBig),
            child: AppPrimaryButton(
              text: 'Continue',
              fullWidth: true,
              borderRadius: DesignConstants.radiusBig,
              onPressed: () => Navigator.of(
                context,
              ).pushReplacementNamed(AppRoutes.videoRecc),
            ),
          ),
        ],
      ),
    );
  }
}

class _CelebrationContent extends StatelessWidget {
  const _CelebrationContent();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: DesignConstants.spacingBig,
      children: [
        Image.asset(
          'assets/images/class_booked_celebration.png',
          fit: BoxFit.contain,
        ),
        Text(
          'Class Booked',
          style: DesignConstants.big2,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
