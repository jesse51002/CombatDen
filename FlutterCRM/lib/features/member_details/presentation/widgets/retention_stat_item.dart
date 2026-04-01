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
      children: [
        Icon(
          icon,
          color: valueColor,
          size: 20,
        ),
        const SizedBox(
          width: DesignConstants.spacingSmall,
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: DesignConstants.h3.copyWith(
                  color: valueColor,
                ),
              ),
              Text(
                label,
                style: DesignConstants.pSmall.copyWith(
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
