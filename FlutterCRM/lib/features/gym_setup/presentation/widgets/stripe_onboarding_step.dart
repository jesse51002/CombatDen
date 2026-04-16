import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/gym_setup/bloc/gym_setup_bloc.dart';
import 'package:crm/features/gym_setup/bloc/gym_setup_event.dart';
import 'package:crm/shared/widgets/app_primary_button.dart';
import 'package:crm/shared/widgets/error_message.dart';

/// Main Stripe onboarding screen. The poller runs
/// while this widget is mounted. The user can
/// (re)open the hosted flow or manually force a
/// status check.
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
          size: 80,
          color: DesignConstants.primaryColor,
          weight: DesignConstants.iconWeight,
        ),
        Text(
          'Finish setting up payments with Stripe',
          style: DesignConstants.h1.copyWith(
            color: DesignConstants.text,
          ),
          textAlign: TextAlign.center,
        ),
        Text(
          'We opened Stripe in a new tab. Complete '
          'the hosted flow and come back here — '
          "we'll update automatically when you're done.",
          style: DesignConstants.p.copyWith(
            color: DesignConstants.text2nd,
          ),
          textAlign: TextAlign.center,
        ),
        if (showBackendTroubleBanner)
          _TroubleBanner(),
        if (requirementsDue.isNotEmpty)
          _RequirementsList(items: requirementsDue),
        if (errorMessage != null)
          ErrorMessage(message: errorMessage!),
        AppPrimaryButton(
          fullWidth: true,
          text: 'Open Stripe onboarding',
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
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(
        DesignConstants.spacingLarge,
      ),
      decoration: BoxDecoration(
        color: DesignConstants.yellowDark,
        borderRadius: BorderRadius.circular(
          DesignConstants.radiusSmall,
        ),
        border: Border.all(
          color: DesignConstants.okYellow,
          width: 1,
        ),
      ),
      child: Row(
        spacing: DesignConstants.spacingMedium,
        children: [
          Icon(
            Symbols.warning_sharp,
            color: DesignConstants.okYellow,
            size: 20,
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
            style: DesignConstants.p.copyWith(
              color: DesignConstants.text,
            ),
          ),
      ],
    );
  }

  String _capitalize(String value) {
    if (value.isEmpty) return value;
    return value[0].toUpperCase() + value.substring(1);
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
            height: 14,
            width: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor:
                  AlwaysStoppedAnimation<Color>(
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
            isPolling ? 'Checking\u2026' : 'Check status now',
            style: DesignConstants.p.copyWith(
              color: DesignConstants.primaryColor,
            ),
          ),
        ),
      ],
    );
  }
}
