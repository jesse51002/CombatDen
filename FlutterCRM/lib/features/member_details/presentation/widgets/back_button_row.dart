import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

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
            Symbols.chevron_left_sharp,
            color: DesignConstants.text2nd,
            weight: DesignConstants.iconWeight,
          ),
          label: Text(
            'Back',
            style: DesignConstants.h2.copyWith(
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
