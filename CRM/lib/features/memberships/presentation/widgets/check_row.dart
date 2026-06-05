import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';

/// A tappable label + checkbox row used in the catalog dialogs
/// (e.g. "Unlimited classes", "Public"). Tokened off
/// [DesignConstants]; the whole row toggles.
class CheckRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const CheckRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: DesignConstants.spacingSmall,
        ),
        child: Row(
          spacing: DesignConstants.spacingMedium,
          children: [
            Icon(
              value
                  ? Symbols.check_box_sharp
                  : Symbols.check_box_outline_blank_sharp,
              color: value
                  ? DesignConstants.primaryColor
                  : DesignConstants.text2nd,
              size: DesignConstants.iconSizeLarge,
              weight: DesignConstants.iconWeight,
            ),
            Expanded(
              child: Text(label, style: DesignConstants.p),
            ),
          ],
        ),
      ),
    );
  }
}
