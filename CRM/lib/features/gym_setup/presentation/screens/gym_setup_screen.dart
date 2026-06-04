import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/navigation/app_routes.dart';
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

/// Multi-step gym setup wizard.
///
/// Hosts [GymSetupBloc] and forwards lifecycle visibility
/// changes so the Stripe poller pauses when backgrounded.
/// The class name and constructor are referenced by
/// `auth_gate.dart` — keep them stable.
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
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final visible = state == AppLifecycleState.resumed;
    _bloc?.add(GymSetupVisibilityChanged(visible: visible));
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
            Navigator.of(context).pushReplacementNamed(
              AppRoutes.home,
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
                    padding: const EdgeInsets.all(
                      DesignConstants.screenHorizontalPadding,
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
    final content = switch (state) {
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
          showBackendTroubleBanner: showBackendTroubleBanner,
          errorMessage: errorMessage,
        ),
      GymSetupDisabledStep(:final disabledReason) =>
        DisabledStep(disabledReason: disabledReason),
      GymSetupComplete(:final gymId) =>
        _CompleteStep(gymId: gymId),
    };

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 500),
      child: Container(
        decoration: BoxDecoration(
          color: DesignConstants.card,
          borderRadius: BorderRadius.circular(
            DesignConstants.radiusSmall,
          ),
          boxShadow: DesignConstants.cardShadow,
        ),
        padding: const EdgeInsets.all(
          DesignConstants.paddingBig,
        ),
        child: content,
      ),
    );
  }
}

/// Shown briefly when setup completes, then navigates
/// to the members workspace.
class _CompleteStep extends StatefulWidget {
  final String gymId;

  const _CompleteStep({required this.gymId});

  @override
  State<_CompleteStep> createState() =>
      _CompleteStepState();
}

class _CompleteStepState extends State<_CompleteStep> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context)
          .pushReplacementNamed(AppRoutes.members);
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
          size: DesignConstants.iconSizeBig * 2.5,
          color: DesignConstants.goodGreen,
          weight: DesignConstants.iconWeight,
        ),
        Text(
          'All set!',
          style: DesignConstants.h1,
          textAlign: TextAlign.center,
        ),
        Text(
          'Taking you to your dashboard…',
          style: DesignConstants.p.copyWith(
            color: DesignConstants.text2nd,
          ),
          textAlign: TextAlign.center,
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
        size: DesignConstants.iconSizeSmall,
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
