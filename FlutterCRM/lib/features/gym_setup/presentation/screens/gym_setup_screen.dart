import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/network/api_client.dart';
import 'package:crm/features/gym_setup/bloc/gym_setup_bloc.dart';
import 'package:crm/features/gym_setup/bloc/gym_setup_event.dart';
import 'package:crm/features/gym_setup/bloc/gym_setup_state.dart';
import 'package:crm/features/gym_setup/data/repositories/gym_repository.dart';
import 'package:crm/features/gym_setup/presentation/widgets/disabled_step.dart';
import 'package:crm/features/gym_setup/presentation/widgets/gym_name_step.dart';
import 'package:crm/features/gym_setup/presentation/widgets/owner_name_step.dart';
import 'package:crm/features/gym_setup/presentation/widgets/resume_step.dart';
import 'package:crm/features/gym_setup/presentation/widgets/stripe_onboarding_step.dart';
import 'package:crm/features/gym_setup/presentation/widgets/welcome_step.dart';
import 'package:crm/features/login/bloc/login_bloc.dart';
import 'package:crm/features/login/bloc/login_event.dart';
import 'package:crm/features/login/bloc/login_state.dart';
import 'package:crm/features/login/presentation/screens/login_screen.dart';
import 'package:crm/features/members_list/presentation/screens/members_list_screen.dart';

/// Multi-step gym setup wizard screen.
///
/// Hosts the [GymSetupBloc] and forwards tab
/// visibility changes so the poller pauses while
/// backgrounded.
class GymSetupScreen extends StatefulWidget {
  const GymSetupScreen({super.key});

  @override
  State<GymSetupScreen> createState() =>
      _GymSetupScreenState();
}

class _GymSetupScreenState extends State<GymSetupScreen>
    with WidgetsBindingObserver {
  GymSetupBloc? _bloc;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(
    AppLifecycleState state,
  ) {
    final visible = state == AppLifecycleState.resumed;
    _bloc?.add(
      GymSetupVisibilityChanged(visible: visible),
    );
  }

  Future<void> _openStripeUrl(String url) async {
    final ok = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
      webOnlyWindowName: '_blank',
    );
    if (!ok) {
      throw Exception('Could not launch $url');
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<GymSetupBloc>(
      create: (_) {
        final bloc = GymSetupBloc(
          gymRepository: GymRepository(
            apiClient: ApiClient(),
          ),
          openUrl: _openStripeUrl,
        )..add(const GymSetupCheckRequested());
        _bloc = bloc;
        return bloc;
      },
      child: BlocListener<LoginBloc, LoginState>(
        listener: (context, state) {
          if (state is LoginUnauthenticated) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute<void>(
                builder: (_) => const LoginScreen(),
              ),
            );
          }
        },
        child: Scaffold(
          backgroundColor:
              DesignConstants.backgroundColor,
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
                      builder: _buildStep,
                    ),
                  ),
                ),
                Positioned(
                  top: DesignConstants.spacingMedium,
                  right: DesignConstants.spacingMedium,
                  child: _LogoutButton(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStep(
    BuildContext context,
    GymSetupState state,
  ) {
    final stepWidget = switch (state) {
      GymSetupInitial() || GymSetupLoading() => Center(
          child: CircularProgressIndicator(
            color: DesignConstants.primaryColor,
          ),
        ),
      GymSetupWelcomeStep() => const WelcomeStep(),
      GymSetupGymNameStep(
        :final errorMessage,
        :final isSubmitting,
      ) =>
        GymNameStep(
          errorMessage: errorMessage,
          isSubmitting: isSubmitting,
        ),
      GymSetupOwnerNameStep(
        :final errorMessage,
        :final isSubmitting,
      ) =>
        OwnerNameStep(
          errorMessage: errorMessage,
          isSubmitting: isSubmitting,
        ),
      GymSetupResumeStep(
        :final errorMessage,
        :final isSubmitting,
      ) =>
        ResumeStep(
          errorMessage: errorMessage,
          isSubmitting: isSubmitting,
        ),
      GymSetupStripeOnboardingStep(
        :final requirementsDue,
        :final isPolling,
        :final showBackendTroubleBanner,
        :final errorMessage,
      ) =>
        StripeOnboardingStep(
          requirementsDue: requirementsDue,
          isPolling: isPolling,
          showBackendTroubleBanner:
              showBackendTroubleBanner,
          errorMessage: errorMessage,
        ),
      GymSetupDisabledStep(:final disabledReason) =>
        DisabledStep(disabledReason: disabledReason),
      GymSetupComplete(:final gymId) =>
        _CompleteAutoNavigator(gymId: gymId),
    };

    return _buildCard(stepWidget);
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
}

/// Navigates to [MembersListScreen] as soon as the
/// complete state is rendered. Keeps the widget tree
/// stable for one frame while the transition runs.
class _CompleteAutoNavigator extends StatefulWidget {
  final String gymId;

  const _CompleteAutoNavigator({required this.gymId});

  @override
  State<_CompleteAutoNavigator> createState() =>
      _CompleteAutoNavigatorState();
}

class _CompleteAutoNavigatorState
    extends State<_CompleteAutoNavigator> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) =>
              MembersListScreen(gymId: widget.gymId),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      spacing: DesignConstants.spacingLarge,
      children: [
        Icon(
          Symbols.check_circle_sharp,
          size: 80,
          color: DesignConstants.goodGreen,
          weight: DesignConstants.iconWeight,
        ),
        Text(
          'All set',
          style: DesignConstants.h1.copyWith(
            color: DesignConstants.text,
          ),
        ),
      ],
    );
  }
}

class _LogoutButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: () {
        context.read<LoginBloc>().add(
              const LoginSignOutRequested(),
            );
      },
      icon: Icon(
        Symbols.logout_sharp,
        color: DesignConstants.text2nd,
        size: 18,
        weight: DesignConstants.iconWeight,
      ),
      label: Text(
        'Logout',
        style: DesignConstants.p.copyWith(
          color: DesignConstants.text2nd,
        ),
      ),
    );
  }
}
