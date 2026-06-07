import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/gym_setup/bloc/gym_setup_bloc.dart';
import 'package:crm/features/gym_setup/bloc/gym_setup_event.dart';
import 'package:crm/shared/widgets/app_primary_button.dart';

/// Welcome step — introduces the setup wizard.
class WelcomeStep extends StatelessWidget {
  const WelcomeStep({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: DesignConstants.spacingLarge,
      children: [
        Icon(
          Symbols.fitness_center_sharp,
          size: DesignConstants.iconSizeBig * 2.5,
          color: DesignConstants.primaryColor,
          weight: DesignConstants.iconWeight,
        ),
        Column(
          spacing: DesignConstants.spacingSmall,
          children: [
            Text(
              "Let's Get Set Up",
              style: DesignConstants.h1,
              textAlign: TextAlign.center,
            ),
            Text(
              "We'll set up your gym and connect payments"
              ' in just a few steps.',
              style: DesignConstants.p.copyWith(
                color: DesignConstants.text2nd,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        AppPrimaryButton(
          fullWidth: true,
          text: 'Get Started',
          onPressed: () {
            context.read<GymSetupBloc>().add(
                  const GymSetupWelcomeContinued(),
                );
          },
        ),
      ],
    );
  }
}
