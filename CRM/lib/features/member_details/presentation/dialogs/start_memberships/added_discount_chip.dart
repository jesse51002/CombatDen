import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';

/// One discount added to a membership on the deals step —
/// a compact removable chip in the membership card's grid.
class AddedDiscountChip extends StatelessWidget {
  final String label;
  final VoidCallback onRemove;

  const AddedDiscountChip({
    super.key,
    required this.label,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(
        DesignConstants.spacingSmall,
      ),
      decoration: BoxDecoration(
        color: DesignConstants.primaryColor10,
        borderRadius: BorderRadius.circular(
          DesignConstants.radiusSmall,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: DesignConstants.spacingSmall,
        children: [
          Flexible(
            child: Text(
              label,
              style: DesignConstants.pSmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          InkWell(
            onTap: onRemove,
            borderRadius: BorderRadius.circular(
              DesignConstants.radiusSmall,
            ),
            child: Icon(
              Symbols.close_sharp,
              weight: DesignConstants.iconWeight,
              size: DesignConstants.iconSizeSmall,
              color: DesignConstants.text2nd,
            ),
          ),
        ],
      ),
    );
  }
}
