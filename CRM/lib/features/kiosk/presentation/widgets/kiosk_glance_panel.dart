import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';

/// The lifted white chrome around each of the glance's two halves. Clips its
/// child so a reward image can bleed to the panel edge; content-agnostic
/// otherwise. The "Get the app" panels wear the same chrome, so [color] /
/// [borderColor] override the fill instead of a second panel widget existing.
class KioskGlancePanel extends StatelessWidget {
  final Widget child;

  /// Fill override — the "Get the app" card's soft accent wash.
  final Color? color;

  /// Border override, paired with [color]. Defaults to the hairline.
  final Color? borderColor;

  const KioskGlancePanel({
    super.key,
    required this.child,
    this.color,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.symmetric(
        horizontal: DesignConstants.paddingBig,
        vertical: DesignConstants.spacingLarge,
      ),
      decoration: BoxDecoration(
        color: color ?? DesignConstants.surface,
        borderRadius: BorderRadius.circular(DesignConstants.radiusCard),
        border: Border.all(color: borderColor ?? DesignConstants.line),
        boxShadow: DesignConstants.cardShadow,
      ),
      child: child,
    );
  }
}
