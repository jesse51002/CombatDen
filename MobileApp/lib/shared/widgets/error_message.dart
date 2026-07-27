import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:mobile_app/core/design_constants.dart';

/// Inline error banner used on the auth and identity screens — a soft red
/// tinted row with an error glyph and the [message]. Adapted from the CRM's
/// `ErrorMessage` so the two apps share one treatment. Tokens from
/// [DesignConstants].
class ErrorMessage extends StatelessWidget {
  const ErrorMessage({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: DesignConstants.badRed.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
        border: Border.all(
          color: DesignConstants.badRed.withValues(alpha: 0.25),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: DesignConstants.paddingSmall,
          vertical: DesignConstants.spacingMedium,
        ),
        child: Row(
          spacing: DesignConstants.spacingMedium,
          children: [
            Icon(
              Symbols.error_sharp,
              size: DesignConstants.iconSizeMd,
              color: DesignConstants.badRed,
              weight: DesignConstants.iconWeight,
            ),
            Expanded(
              child: Text(
                message,
                style: DesignConstants.p.copyWith(
                  color: DesignConstants.badRed,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
