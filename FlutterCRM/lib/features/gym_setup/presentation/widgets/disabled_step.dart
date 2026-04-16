import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';

/// Terminal state — Stripe has disabled the gym's
/// connected account. No in-app remediation; the
/// owner must contact support.
class DisabledStep extends StatelessWidget {
  final String? disabledReason;

  const DisabledStep({
    super.key,
    required this.disabledReason,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: DesignConstants.spacingLarge,
      children: [
        Icon(
          Symbols.error_sharp,
          size: 80,
          color: DesignConstants.badRed,
          weight: DesignConstants.iconWeight,
        ),
        Text(
          'Your Stripe account is disabled',
          style: DesignConstants.h1.copyWith(
            color: DesignConstants.text,
          ),
          textAlign: TextAlign.center,
        ),
        Text(
          'Please contact support.',
          style: DesignConstants.p.copyWith(
            color: DesignConstants.text2nd,
          ),
          textAlign: TextAlign.center,
        ),
        if (disabledReason != null)
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(
              DesignConstants.spacingLarge,
            ),
            decoration: BoxDecoration(
              color: DesignConstants.redDark,
              borderRadius: BorderRadius.circular(
                DesignConstants.radiusSmall,
              ),
            ),
            child: Text(
              disabledReason!,
              style: DesignConstants.p.copyWith(
                color: DesignConstants.badRed,
              ),
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }
}
