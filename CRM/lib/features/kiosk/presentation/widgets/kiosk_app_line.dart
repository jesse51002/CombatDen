import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';

/// The muted "get / use the CombatDen app" line — a tiny brand glyph beside a
/// soft caption (mockup `.app-line`). A calm nudge, never a loud CTA.
class KioskAppLine extends StatelessWidget {
  final String text;

  const KioskAppLine({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingSmall,
      children: [
        Container(
          width: DesignConstants.spinnerSizeSmall,
          height: DesignConstants.spinnerSizeSmall,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: DesignConstants.primaryGradient,
            borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
          ),
          child: Icon(
            Symbols.adjust_sharp,
            size: DesignConstants.iconSizeTiny,
            weight: DesignConstants.iconWeight,
            color: DesignConstants.onAccent,
          ),
        ),
        Flexible(
          child: Text(
            text,
            style: DesignConstants.kioskCaption.copyWith(
              color: DesignConstants.text2nd,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}
