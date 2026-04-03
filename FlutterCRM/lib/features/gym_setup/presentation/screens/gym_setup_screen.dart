import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/login/bloc/login_bloc.dart';
import 'package:crm/features/login/bloc/login_event.dart';
import 'package:crm/features/login/bloc/login_state.dart';
import 'package:crm/features/login/presentation/screens/login_screen.dart';
import 'package:crm/features/gym_setup/bloc/gym_setup_bloc.dart';
import 'package:crm/features/gym_setup/bloc/gym_setup_event.dart';
import 'package:crm/features/gym_setup/bloc/gym_setup_state.dart';
import 'package:crm/features/gym_setup/data/repositories/gym_repository.dart';
import 'package:crm/features/home/presentation/screens/home_screen.dart';
import 'package:crm/features/gym_setup/presentation/widgets/welcome_step.dart';
import 'package:crm/features/gym_setup/presentation/widgets/gym_name_step.dart';
import 'package:crm/features/gym_setup/presentation/widgets/owner_name_step.dart';
import 'package:crm/shared/widgets/app_primary_button.dart';

/// Multi-step gym setup wizard screen
class GymSetupScreen extends StatelessWidget {
  const GymSetupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final userId = Supabase
        .instance.client.auth.currentUser!.id;

    return BlocProvider(
      create: (_) => GymSetupBloc(
        gymRepository: GymRepository(),
        userId: userId,
      )..add(const GymSetupCheckRequested()),
      child: BlocListener<LoginBloc, LoginState>(
        listener: (context, state) {
          if (state is LoginUnauthenticated) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (_) => const LoginScreen(),
              ),
            );
          }
        },
        child: Scaffold(
          backgroundColor: DesignConstants.backgroundColor,
          body: SafeArea(
            child: Stack(
              children: [
                Center(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.all(
                      DesignConstants
                          .screenHorizontalPadding,
                    ),
                    child: BlocBuilder<GymSetupBloc,
                        GymSetupState>(
                      builder: (context, state) {
                        final stepWidget =
                            switch (state) {
                          GymSetupInitial() ||
                          GymSetupLoading() =>
                            Center(
                              child:
                                  CircularProgressIndicator(
                                color: DesignConstants
                                    .primaryColor,
                              ),
                            ),
                          GymSetupWelcomeStep() =>
                            const WelcomeStep(),
                          GymSetupGymNameStep() =>
                            GymNameStep(
                              errorMessage:
                                  state.errorMessage,
                              isSubmitting:
                                  state.isSubmitting,
                            ),
                          GymSetupOwnerNameStep() =>
                            OwnerNameStep(
                              errorMessage:
                                  state.errorMessage,
                              isSubmitting:
                                  state.isSubmitting,
                            ),
                          GymSetupComplete() =>
                            _buildCompleteView(
                              context,
                            ),
                        };

                        return _buildCard(stepWidget);
                      },
                    ),
                  ),
                ),
                Positioned(
                  top: DesignConstants.spacingMedium
                      ,
                  right: DesignConstants.spacingMedium
                      ,
                  child: TextButton.icon(
                    onPressed: () {
                      context.read<LoginBloc>().add(
                            const LoginSignOutRequested(),
                          );
                    },
                    icon: Icon(
                      Symbols.logout_sharp,
                      color: DesignConstants.text
                          .withValues(alpha: 0.7),
                      size: 18,
                      weight: DesignConstants.iconWeight,
                    ),
                    label: Text(
                      'Logout',
                      style: DesignConstants.p.copyWith(
                        color: DesignConstants.text
                            .withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCard(Widget child) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 500),
      child: Container(
        decoration: BoxDecoration(
          color: DesignConstants.card,
          borderRadius: BorderRadius.circular(
            DesignConstants.radiusSmall,
          ),
        ),
        padding: EdgeInsets.all(
          DesignConstants.paddingBig,
        ),
        child: child,
      ),
    );
  }

  Widget _buildCompleteView(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Symbols.check_circle_sharp,
          size: 80,
          color: DesignConstants.goodGreen,
          weight: DesignConstants.iconWeight,
        ),
        SizedBox(
          height:
              DesignConstants.spacingLarge,
        ),
        Text(
          'Basic Setup Complete!',
          style: DesignConstants.h1.copyWith(
            color: DesignConstants.text,
          ),
        ),
        SizedBox(
          height:
              DesignConstants.spacingMedium,
        ),
        Text(
          'Your gym is ready to go.',
          style: DesignConstants.p.copyWith(
            color: DesignConstants.text
                .withValues(alpha: 0.7),
          ),
        ),
        SizedBox(
          height:
              DesignConstants.spacingBig,
        ),
        AppPrimaryButton(fullWidth: true,
          text: 'Finish',
          onPressed: () {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (_) => const HomeScreen(),
              ),
            );
          },
        ),
      ],
    );
  }
}
