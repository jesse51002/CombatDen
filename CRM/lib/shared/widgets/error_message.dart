import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';

/// Inline error banner used on auth and form screens.
///
/// Renders a soft red tinted row with an error icon and the
/// [message] text. All visual tokens come from [DesignConstants].
class ErrorMessage extends StatelessWidget {
  final String message;

  const ErrorMessage({super.key, required this.message});

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
              size: DesignConstants.iconSizeMedium,
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
