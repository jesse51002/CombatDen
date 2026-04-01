import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';

/// A back button row with chevron icon and "Back" text.
class BackButtonRow extends StatelessWidget {
  const BackButtonRow({super.key});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(
          left: DesignConstants.spacingLarge,
          top: DesignConstants.spacingSmall,
          bottom: DesignConstants.spacingSmall,
        ),
        child: TextButton.icon(
          onPressed: () => Navigator.of(context).pop(),
          icon: Icon(
            Icons.chevron_left,
            color: DesignConstants.text2nd,
          ),
          label: Text(
            'Back',
            style: DesignConstants.p.copyWith(
              color: DesignConstants.text2nd,
            ),
          ),
          style: TextButton.styleFrom(
            foregroundColor: DesignConstants.text2nd,
          ),
        ),
      ),
    );
  }
}
