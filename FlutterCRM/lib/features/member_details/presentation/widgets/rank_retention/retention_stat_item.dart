import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';

/// A retention stat display with icon, colored value,
/// and label text.
class RetentionStatItem extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color valueColor;

  const RetentionStatItem({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      spacing: DesignConstants.spacingMedium,
      children: [
        Icon(
          icon,
          color: valueColor,
          size: 40,
          weight: DesignConstants.iconWeight,
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: DesignConstants.h2.copyWith(
                  color: valueColor,
                ),
              ),
              Text(
                label,
                style: DesignConstants.h3.copyWith(
                  color: DesignConstants.text2nd,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
