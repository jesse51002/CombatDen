import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';

/// A quiet trailing control on a roster row — the Edit that reopens somebody's
/// details, and the trash that takes them off it. One widget for both, so the
/// two never drift to different sizes on a row where they sit side by side.
///
/// [semanticLabel] names the PERSON as well as the verb ("Edit Ella Bell"),
/// since a screen reader hearing four bare "Edit"s down a family roster learns
/// nothing; the visible label stays short because the row already says who.
class KioskRowAction extends StatelessWidget {
  final String semanticLabel;
  final IconData icon;

  /// The visible word beside the glyph. Null leaves the glyph alone.
  final String? label;

  final VoidCallback onTap;

  const KioskRowAction({
    super.key,
    required this.semanticLabel,
    required this.icon,
    required this.onTap,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    final word = label;
    return Semantics(
      label: semanticLabel,
      button: true,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
        child: Padding(
          padding: const EdgeInsets.all(DesignConstants.spacingMedium),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: DesignConstants.spacingSmall,
            children: [
              Icon(
                icon,
                size: word == null
                    ? DesignConstants.iconSizeMedium
                    : DesignConstants.iconSizeSmall,
                weight: DesignConstants.iconWeight,
                color: DesignConstants.text2nd,
              ),
              if (word != null)
                Text(
                  word,
                  style: DesignConstants.kioskCaption.copyWith(
                    color: DesignConstants.text2nd,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
