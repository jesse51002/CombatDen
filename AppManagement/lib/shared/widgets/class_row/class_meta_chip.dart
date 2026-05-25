import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';

/// Small metadata chip: an icon followed by a label, in [color]. Used for
/// "points", "attending", and "checked in" on class widgets.
class ClassMetaChip extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const ClassMetaChip({
    super.key,
    required this.icon,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: DesignConstants.spacingSmall,
      children: [
        Icon(icon, size: DesignConstants.iconSizeTiny, color: color, weight: DesignConstants.iconWeight),
        Text(text, style: DesignConstants.p.copyWith(color: color)),
      ],
    );
  }
}
