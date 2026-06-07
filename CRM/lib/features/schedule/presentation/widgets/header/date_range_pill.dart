import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';

/// Card-styled rounded pill that shows the visible week range
/// (e.g. "Feb 1st, 2026 - Feb 7th, 2026") and a chevron-down hint that
/// it can be opened to pick a different range.
///
/// Demo-only — tapping it logs a TODO via `debugPrint`.
class DateRangePill extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const DateRangePill({
    super.key,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
      child: Container(
        height: 40,
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
