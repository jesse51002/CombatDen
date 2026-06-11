import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';

/// Inline warning banner — the cautionary sibling of
/// [ErrorMessage] (`error_message.dart`): same tinted-row
/// shape, in the `okYellow` warning palette with a warning
/// icon. For prominent heads-ups that aren't failures
/// (e.g. "the card will be charged twice today").
class WarningMessage extends StatelessWidget {
  final String message;

  const WarningMessage({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: DesignConstants.okYellow.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
        border: Border.all(
          color: DesignConstants.okYellow.withValues(alpha: 0.25),
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
              Symbols.warning_sharp,
              size: DesignConstants.iconSizeMedium,
              color: DesignConstants.okYellow,
              weight: DesignConstants.iconWeight,
            ),
            Expanded(
              child: Text(
                message,
                style: DesignConstants.p.copyWith(
                  color: DesignConstants.okYellow,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
