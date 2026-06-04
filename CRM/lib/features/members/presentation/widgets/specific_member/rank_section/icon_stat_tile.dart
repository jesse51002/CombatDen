import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';

/// A horizontal icon + 2-line label tile used inside the rank and
/// retention grids on the SpecificMember screen.
///
/// Top line is the bold value (e.g. "10 classes", "5 days ago").
/// Bottom line is the dim caption (e.g. "Classes In Rank").
class IconStatTile extends StatelessWidget {
  final IconData icon;
  final double iconSize;
  final String value;
  final String caption;
  final Color? valueColor;

  const IconStatTile({
    super.key,
    required this.icon,
    required this.value,
    required this.caption,
    this.iconSize = DesignConstants.iconSizeBig,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingLarge,
      children: [
        Icon(
          icon,
          size: iconSize,
          color: DesignConstants.text,
          weight: DesignConstants.iconWeight,
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: DesignConstants.spacingSmall,
          children: [
            Text(
              value,
              style: DesignConstants.h2.copyWith(
                color: valueColor ?? DesignConstants.text,
              ),
            ),
            Text(
              caption,
              style: DesignConstants.p.copyWith(
                color: DesignConstants.text2nd,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
