import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/shared/widgets/buttons/app_primary_button.dart';
import 'package:mobile_app/shared/widgets/error_message.dart';

/// Designed error state for the schedule board: the failure message with a
/// retry action (never a blank column).
class HomeErrorView extends StatelessWidget {
  const HomeErrorView({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: DesignConstants.screenHorizontalPadding,
        vertical: DesignConstants.spacingBig,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingLarge,
        children: [
          ErrorMessage(message: message),
          Center(
            child: AppPrimaryButton(
              text: 'Try again',
              onPressed: onRetry,
            ),
          ),
        ],
      ),
    );
  }
}
