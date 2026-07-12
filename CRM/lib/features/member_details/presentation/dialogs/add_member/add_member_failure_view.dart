import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';

/// Blocking failure panel for the add-member create step. When
/// [needsStripeSetup] (the gym has no Stripe Connect account), it points the
/// user at Settings rather than showing a bare error.
class AddMemberFailureView extends StatelessWidget {
  final String message;
  final bool needsStripeSetup;

  const AddMemberFailureView({
    super.key,
    required this.message,
    required this.needsStripeSetup,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingLarge,
      children: [
        Icon(
          Symbols.error_sharp,
          size: DesignConstants.iconSizeBig,
          weight: DesignConstants.iconWeight,
          color: DesignConstants.badRed,
        ),
        Text(
          "Couldn't add this member",
          style: DesignConstants.h2,
        ),
        Text(
          message,
          style: DesignConstants.p.copyWith(
            color: DesignConstants.text2nd,
          ),
        ),
        if (needsStripeSetup)
          Container(
            padding: const EdgeInsets.all(
              DesignConstants.paddingSmall,
            ),
            decoration: BoxDecoration(
              color: DesignConstants.okYellow.withValues(alpha: 0.12),
              borderRadius:
                  BorderRadius.circular(DesignConstants.radiusSmall),
              border: Border.all(color: DesignConstants.okYellow),
            ),
            child: Text(
              'This gym needs a connected payment account before members '
              'can be created. Finish payment setup in Settings, then try '
              'again.',
              style: DesignConstants.pSmall.copyWith(
                color: DesignConstants.text,
              ),
            ),
          ),
      ],
    );
  }
}
