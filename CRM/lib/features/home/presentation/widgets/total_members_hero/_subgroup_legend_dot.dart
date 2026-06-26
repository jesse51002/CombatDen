import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';

/// One legend entry below the arc — colored dot + "Active: 123" / etc.
class SubgroupLegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const SubgroupLegendDot({
    super.key,
    required this.color,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: DesignConstants.spacingSmall,
      children: [
        Container(
          width: DesignConstants.legendDotSize,
          height: DesignConstants.legendDotSize,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        Text(
          label,
          style: DesignConstants.h2Regular.copyWith(
            color: DesignConstants.text,
          ),
        ),
      ],
    );
  }
}
