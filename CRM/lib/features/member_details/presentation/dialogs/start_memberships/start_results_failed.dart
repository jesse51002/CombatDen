import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';

/// The whole request was rejected (HTTP 400 validation /
/// transport failure) — nothing was charged or created.
class StartResultsFailed extends StatelessWidget {
  final String error;
  final VoidCallback onBackToPayment;

  const StartResultsFailed({
    super.key,
    required this.error,
    required this.onBackToPayment,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingLarge,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: DesignConstants.spacingSmall,
          children: [
            Text(
              'The request was not accepted',
              style: DesignConstants.h2.copyWith(
                color: DesignConstants.badRed,
              ),
            ),
            Text(error, style: DesignConstants.p),
          ],
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: AppOutlineButton(
            text: 'Back to payment',
            borderRadius: DesignConstants.radiusSmall,
            onPressed: onBackToPayment,
          ),
        ),
      ],
    );
  }
}
