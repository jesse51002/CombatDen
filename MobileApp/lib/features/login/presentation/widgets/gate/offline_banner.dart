import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:mobile_app/core/design_constants.dart';

/// A slim, dismissible banner shown above the app when it booted read-degraded
/// from the cached selection (the identity fetch was offline). Offers a retry.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({
    super.key,
    required this.onRetry,
    required this.onDismiss,
  });

  final VoidCallback onRetry;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: DesignConstants.card,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: DesignConstants.paddingSmall,
          vertical: DesignConstants.spacingMedium,
        ),
        child: Row(
          spacing: DesignConstants.spacingMedium,
          children: [
            Icon(
              Symbols.cloud_off_sharp,
              weight: DesignConstants.iconWeight,
              color: DesignConstants.text2nd,
              size: DesignConstants.iconSizeSm,
            ),
            Expanded(
              child: Text(
                "You're offline — showing your last data.",
                style: DesignConstants.pSmall.copyWith(
                  color: DesignConstants.text2nd,
                ),
              ),
            ),
            GestureDetector(
              onTap: onRetry,
              child: Text(
                'Retry',
                style: DesignConstants.pSmall.copyWith(
                  color: DesignConstants.primaryColor,
                ),
              ),
            ),
            GestureDetector(
              onTap: onDismiss,
              child: Icon(
                Symbols.close_sharp,
                weight: DesignConstants.iconWeight,
                color: DesignConstants.text3rd,
                size: DesignConstants.iconSizeSm,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
