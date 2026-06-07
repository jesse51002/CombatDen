import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/gym_setup/bloc/gym_setup_bloc.dart';
import 'package:crm/features/gym_setup/bloc/gym_setup_event.dart';
import 'package:crm/shared/widgets/app_primary_button.dart';
import 'package:crm/features/gym_setup/presentation/widgets/step_error_banner.dart';

/// Main Stripe onboarding screen. Polls status in the
/// background while the user completes the hosted flow.
class StripeOnboardingStep extends StatelessWidget {
  final List<String> requirementsDue;
  final bool isPolling;
  final bool showBackendTroubleBanner;
  final String? errorMessage;

  const StripeOnboardingStep({
    super.key,
    required this.requirementsDue,
    required this.isPolling,
    required this.showBackendTroubleBanner,
    this.errorMessage,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingLarge,
      children: [
        Icon(
          Symbols.payments_sharp,
          size: DesignConstants.iconSizeBig * 2.5,
          color: DesignConstants.primaryColor,
          weight: DesignConstants.iconWeight,
        ),
        Column(
          spacing: DesignConstants.spacingSmall,
          children: [
            Text(
              'Connect Stripe to accept payments',
              style: DesignConstants.h1,
              textAlign: TextAlign.center,
            ),
            Text(
              'We opened Stripe in a new tab. Complete '
              'the hosted flow and come back — '
              "we'll update automatically when you're done.",
              style: DesignConstants.p.copyWith(
                color: DesignConstants.text2nd,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        if (showBackendTroubleBanner)
          const _TroubleBanner(),
        if (requirementsDue.isNotEmpty)
          _RequirementsList(items: requirementsDue),
        if (errorMessage != null)
          StepErrorBanner(message: errorMessage!),
        AppPrimaryButton(
          fullWidth: true,
          text: 'Connect Stripe',
          onPressed: () {
            context.read<GymSetupBloc>().add(
                  const GymSetupStripeOpenRequested(),
                );
          },
        ),
        _CheckStatusRow(isPolling: isPolling),
      ],
    );
  }
}

class _TroubleBanner extends StatelessWidget {
  const _TroubleBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(
        DesignConstants.spacingLarge,
      ),
      decoration: BoxDecoration(
        color: DesignConstants.yellowDark,
        borderRadius: BorderRadius.circular(
          DesignConstants.radiusSmall,
        ),
        border: Border.all(
          color: DesignConstants.okYellow,
        ),
      ),
      child: Row(
        spacing: DesignConstants.spacingMedium,
        children: [
          Icon(
            Symbols.warning_sharp,
            color: DesignConstants.okYellow,
            size: DesignConstants.iconSizeMedium,
            weight: DesignConstants.iconWeight,
          ),
          Expanded(
            child: Text(
              'Having trouble reaching the server — '
              'still trying.',
              style: DesignConstants.p.copyWith(
                color: DesignConstants.text,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RequirementsList extends StatelessWidget {
  final List<String> items;

  const _RequirementsList({required this.items});

  String _capitalize(String value) {
    if (value.isEmpty) return value;
    return value[0].toUpperCase() + value.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingSmall,
      children: [
        Text(
          'Still needed by Stripe:',
          style: DesignConstants.h3.copyWith(
            color: DesignConstants.text2nd,
          ),
        ),
        for (final item in items)
          Text(
            '• ${_capitalize(item)}',
            style: DesignConstants.p,
          ),
      ],
    );
  }
}

class _CheckStatusRow extends StatelessWidget {
  final bool isPolling;

  const _CheckStatusRow({required this.isPolling});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      spacing: DesignConstants.spacingMedium,
      children: [
        if (isPolling)
          SizedBox(
            height: DesignConstants.iconSizeSmall,
            width: DesignConstants.iconSizeSmall,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(
                DesignConstants.text2nd,
              ),
            ),
          ),
        TextButton(
          onPressed: isPolling
              ? null
              : () {
                  context.read<GymSetupBloc>().add(
                        const GymSetupStripePollNow(),
                      );
                },
          child: Text(
            isPolling
                ? 'Checking…'
                : 'Check status now',
            style: DesignConstants.p.copyWith(
              color: DesignConstants.primaryColor,
            ),
          ),
        ),
      ],
    );
  }
}
