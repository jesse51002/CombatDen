import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:app_management/core/constants/design_constants.dart';

/// A removable pill-shaped filter chip.
///
/// Displays a filter description with a close button
/// to remove it.
class ActiveFilterChip extends StatelessWidget {
  final String label;
  final VoidCallback onRemoved;

  const ActiveFilterChip({
    super.key,
    required this.label,
    required this.onRemoved,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label, remove filter',
      button: true,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: DesignConstants.paddingSmall,
          vertical: DesignConstants.spacingMedium,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(
            DesignConstants.radiusBig,
          ),
          border: Border.all(
            color: DesignConstants.text,
            width: DesignConstants.buttonBorderSize,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: DesignConstants.spacingSmall,
          children: [
            Text(
              label,
              style: DesignConstants.p.copyWith(
                color: DesignConstants.text2nd,
              ),
            ),
            GestureDetector(
              onTap: onRemoved,
              child: Icon(
                Symbols.close_sharp,
                size: 14,
                color: DesignConstants.text3rd,
                weight: DesignConstants.iconWeight,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
