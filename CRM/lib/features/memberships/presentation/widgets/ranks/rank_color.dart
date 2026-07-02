import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';

final _hexColor = RegExp(r'^#([0-9A-Fa-f]{6})$');

/// Parses a `#RRGGBB` rank colour into a [Color], or null if the
/// string isn't a valid 6-digit hex.
Color? parseRankColor(String? hex) {
  if (hex == null) return null;
  final match = _hexColor.firstMatch(hex.trim());
  if (match == null) return null;
  return Color(0xFF000000 | int.parse(match.group(1)!, radix: 16));
}

/// A small rounded colour chip for a rank's belt colour. Falls back
/// to a neutral swatch when the colour is unset/invalid.
class RankColorSwatch extends StatelessWidget {
  final String? color;
  final double size;

  const RankColorSwatch({
    super.key,
    required this.color,
    this.size = DesignConstants.iconSizeLarge,
  });

  @override
  Widget build(BuildContext context) {
    final resolved = parseRankColor(color) ?? DesignConstants.text3rd;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: resolved,
        borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
        border: Border.all(
          color: DesignConstants.text3rd.withValues(alpha: 0.4),
        ),
      ),
    );
  }
}
