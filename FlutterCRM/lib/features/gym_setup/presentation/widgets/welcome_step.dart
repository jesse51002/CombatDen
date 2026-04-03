import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/shared/widgets/app_primary_button.dart';
import 'package:crm/features/gym_setup/bloc/gym_setup_bloc.dart';
import 'package:crm/features/gym_setup/bloc/gym_setup_event.dart';

/// Welcome step: introduces the setup process
class WelcomeStep extends StatelessWidget {
  const WelcomeStep({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Symbols.fitness_center_sharp,
          size: 80,
          color: DesignConstants.primaryColor,
          weight: DesignConstants.iconWeight,
        ),
        SizedBox(
          height:
              DesignConstants.spacingBig,
        ),
        Text(
          "Let's Get Set Up",
          style: DesignConstants.h1.copyWith(
            color: DesignConstants.text,
          ),
          textAlign: TextAlign.center,
        ),
        SizedBox(
          height:
              DesignConstants.spacingSmall,
        ),
        Text(
          "We'll set up your gym and profile"
          ' in just a couple of steps.',
          style: DesignConstants.p.copyWith(
            color: DesignConstants.text
                .withValues(alpha: 0.7),
          ),
          textAlign: TextAlign.center,
        ),
        SizedBox(
          height:
              DesignConstants.spacingBig,
        ),
        AppPrimaryButton(fullWidth: true,
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
