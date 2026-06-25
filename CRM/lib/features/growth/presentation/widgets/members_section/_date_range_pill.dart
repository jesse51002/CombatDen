import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';

/// "Feb 2025 - Now | Year v" pill in the Members section header.
/// The two halves split by a thin vertical divider both no-op tap.
class DateRangePill extends StatelessWidget {
  final String rangeLabel;
  final String granularityLabel;
  final VoidCallback? onRangeTap;
  final VoidCallback? onGranularityTap;

  const DateRangePill({
    super.key,
    required this.rangeLabel,
    required this.granularityLabel,
    this.onRangeTap,
    this.onGranularityTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignConstants.paddingSmall,
        vertical: DesignConstants.spacingMedium,
      ),
      decoration: BoxDecoration(
        color: DesignConstants.card,
        borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: DesignConstants.spacingLarge,
        children: [
          InkWell(
            onTap: onRangeTap,
            child: Text(
              rangeLabel,
              style: DesignConstants.h2,
            ),
          ),
          Container(
            width: DesignConstants.dividerThickness,
            height: DesignConstants.verticalDividerHeight,
            color: DesignConstants.text3rd,
          ),
          InkWell(
            onTap: onGranularityTap,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: DesignConstants.spacingSmall,
              children: [
                Text(
                  granularityLabel,
                  style: DesignConstants.h2,
                ),
                Icon(
                  Symbols.keyboard_arrow_down_sharp,
                  weight: DesignConstants.iconWeight,
                  color: DesignConstants.text,
                  size: DesignConstants.iconSizeTiny,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
