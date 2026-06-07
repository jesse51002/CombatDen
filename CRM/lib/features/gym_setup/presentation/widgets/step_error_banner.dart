import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';

/// Inline error banner used by each wizard step to
/// surface backend or validation errors.
class StepErrorBanner extends StatelessWidget {
  final String message;

  const StepErrorBanner({
    super.key,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(
        DesignConstants.spacingLarge,
      ),
      decoration: BoxDecoration(
        color: DesignConstants.redDark,
        borderRadius: BorderRadius.circular(
          DesignConstants.radiusSmall,
        ),
        border: Border.all(
          color: DesignConstants.badRed,
        ),
      ),
      child: Row(
        spacing: DesignConstants.spacingMedium,
        children: [
          Icon(
            Symbols.error_sharp,
            color: DesignConstants.badRed,
            size: DesignConstants.iconSizeMedium,
            weight: DesignConstants.iconWeight,
          ),
          Expanded(
            child: Text(
              message,
              style: DesignConstants.p.copyWith(
                color: DesignConstants.text,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
