import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/shared/widgets/buttons/app_primary_button.dart';

/// Loading (null [message]) / error / empty chrome for a rewards grid, shared
/// by the Points Store and My Rewards. Pass [onRetry] to render a retry button
/// under the message (the retry-able error state).
class RewardsLoadStatus extends StatelessWidget {
  const RewardsLoadStatus(this.message, {super.key, this.onRetry});

  final String? message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(DesignConstants.paddingBig),
      child: Center(
        child: message == null
            ? SizedBox(
                height: 24,
                width: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: DesignConstants.primaryColor,
                ),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                spacing: DesignConstants.spacingLarge,
                children: [
                  Text(
                    message!,
                    style: DesignConstants.p.copyWith(
                      color: DesignConstants.text2nd,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (onRetry != null)
                    AppPrimaryButton(text: 'Try again', onPressed: onRetry),
                ],
              ),
      ),
    );
  }
}
