import 'package:flutter/material.dart';

import 'package:mobile_app/core/design_constants.dart';

/// A calm, helpful note for the auth flow: a glyph beside a short line of
/// guidance in a soft primary-tinted container. Unlike [ErrorMessage] (a red
/// failure banner) this reads as help, not alarm — used for load-bearing
/// instructions like "use the email your gym has on file". Tokens from
/// [DesignConstants].
class InfoNote extends StatelessWidget {
  const InfoNote({
    super.key,
    required this.icon,
    required this.message,
  });

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: DesignConstants.primaryCard,
        borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: DesignConstants.paddingSmall,
          vertical: DesignConstants.spacingMedium,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: DesignConstants.spacingMedium,
          children: [
            Icon(
              icon,
              size: DesignConstants.iconSizeSm,
              color: DesignConstants.primaryColor,
              weight: DesignConstants.iconWeight,
            ),
            Expanded(
              child: Text(
                message,
                style: DesignConstants.pSmall.copyWith(
                  color: DesignConstants.text2nd,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
