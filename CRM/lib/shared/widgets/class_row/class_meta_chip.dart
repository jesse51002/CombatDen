import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';

/// Small metadata chip: an icon followed by a label, in [color]. Used for
/// "points", "attending", and "checked in" on class widgets.
class ClassMetaChip extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  /// Label style override — the admin body size (`p`) by default. The kiosk
  /// class card passes a kiosk-ramp token so the chip scales with the rest of
  /// that card's type instead of staying at admin scale.
  final TextStyle? textStyle;

  const ClassMetaChip({
    super.key,
    required this.icon,
    required this.text,
    required this.color,
    this.textStyle,
  });

  @override
  Widget build(BuildContext context) {
    final style = textStyle ?? DesignConstants.p;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: DesignConstants.spacingSmall,
      children: [
        Icon(icon, size: DesignConstants.iconSizeTiny, color: color, weight: DesignConstants.iconWeight),
        Text(text, style: style.copyWith(color: color)),
      ],
    );
  }
}
