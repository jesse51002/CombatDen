import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';

/// A centered section heading for the kiosk home halves: a kiosk-scale
/// sub-title over a muted explanatory line (mockup `.sub-title` + `.sub-text`).
class KioskSectionHead extends StatelessWidget {
  final String title;
  final String subtitle;

  const KioskSectionHead({
    super.key,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingSmall,
      children: [
        Text(
          title,
          style: DesignConstants.kioskTitle,
          textAlign: TextAlign.center,
        ),
        Text(
          subtitle,
          style: DesignConstants.kioskSectionText.copyWith(
            color: DesignConstants.text2nd,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
