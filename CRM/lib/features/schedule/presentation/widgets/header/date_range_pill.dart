import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';

/// Card-styled rounded pill that shows the visible week range
/// (e.g. "Feb 1, 2026 - Feb 7, 2026"). Display-only by default; pass an
/// [onTap] to make it tappable (with a chevron-down affordance) when a
/// range-picker is wired up.
class DateRangePill extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;

  const DateRangePill({
    super.key,
    required this.label,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
      child: Container(
        height: DesignConstants.pillControlHeight,
        padding: const EdgeInsets.symmetric(
          horizontal: DesignConstants.paddingSmall,
        ),
        decoration: BoxDecoration(
          color: DesignConstants.card,
          borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: DesignConstants.spacingSmall,
          children: [
            Text(label, style: DesignConstants.h2),
            if (onTap != null)
              Icon(
                Symbols.expand_more_sharp,
                weight: DesignConstants.iconWeight,
                size: DesignConstants.iconSizeTiny,
                color: DesignConstants.text,
              ),
          ],
        ),
      ),
    );
  }
}
