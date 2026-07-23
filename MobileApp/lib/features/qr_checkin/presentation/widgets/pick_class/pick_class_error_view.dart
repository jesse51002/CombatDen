import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/shared/widgets/buttons/app_primary_button.dart';
import 'package:mobile_app/shared/widgets/error_message.dart';

/// Designed error state for the pick-class step: the failure message with a
/// retry action. Same treatment as the home board's error view, self-contained
/// for this feature.
class PickClassErrorView extends StatelessWidget {
  const PickClassErrorView({
    super.key,
    required this.message,
    required this.onRetry,
  });

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
            child: AppPrimaryButton(text: 'Try again', onPressed: onRetry),
          ),
        ],
      ),
    );
  }
}
