import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';

/// A single read-only field in a detail panel: a small icon + label on top,
/// a larger, prominent value beneath. Unlike [InfoRow] (an inline
/// "label: value" line sized for dense lists), this is built for a panel
/// where the value is the primary thing being read — the label stays
/// legible but visually subordinate.
class DetailField extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  /// Optional secondary line under [value], for a small qualifier the value
  /// alone doesn't spell out (e.g. a duration beside a start–end time range).
  final String? caption;

  const DetailField({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.caption,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingSmall,
      children: [
        Row(
          spacing: DesignConstants.spacingSmall,
          children: [
            Icon(
              icon,
              size: DesignConstants.iconSizeSmall,
              color: DesignConstants.text2nd,
              weight: DesignConstants.iconWeight,
            ),
            Text(
              label,
              style: DesignConstants.h3.copyWith(
                color: DesignConstants.text2nd,
              ),
            ),
          ],
        ),
        Text(
          value,
          style: DesignConstants.h2,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        if (caption != null)
          Text(
            caption!,
            style: DesignConstants.pSmall.copyWith(
              color: DesignConstants.text3rd,
            ),
          ),
      ],
    );
  }
}
