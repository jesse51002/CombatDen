import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/gym_setup/bloc/gym_setup_bloc.dart';
import 'package:crm/features/gym_setup/bloc/gym_setup_event.dart';
import 'package:crm/shared/widgets/app_primary_button.dart';
import 'package:crm/shared/widgets/error_message.dart';

/// Shown when bootstrap finds a gym in `pending`
/// state. Gives the user an explicit "Continue setup"
/// action rather than auto-launching Stripe.
class ResumeStep extends StatelessWidget {
  final String? errorMessage;
  final bool isSubmitting;

  const ResumeStep({
    super.key,
    this.errorMessage,
    this.isSubmitting = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: DesignConstants.spacingLarge,
      children: [
        Icon(
          Symbols.pending_sharp,
          size: 80,
          color: DesignConstants.primaryColor,
          weight: DesignConstants.iconWeight,
        ),
        Text(
          'You have a setup in progress',
          style: DesignConstants.h1.copyWith(
            color: DesignConstants.text,
          ),
          textAlign: TextAlign.center,
        ),
        Text(
          "Your Stripe onboarding didn't finish. "
          'Continue where you left off to start '
          'accepting payments.',
          style: DesignConstants.p.copyWith(
            color: DesignConstants.text2nd,
          ),
          textAlign: TextAlign.center,
        ),
        if (errorMessage != null)
          ErrorMessage(message: errorMessage!),
        AppPrimaryButton(
          fullWidth: true,
          text: 'Continue setup',
          isLoading: isSubmitting,
          onPressed: isSubmitting
              ? null
              : () {
                  context.read<GymSetupBloc>().add(
                        const GymSetupResumeAccepted(),
                      );
                },
        ),
      ],
    );
  }
}
