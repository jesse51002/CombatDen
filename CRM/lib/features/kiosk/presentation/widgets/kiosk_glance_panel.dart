import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';

/// The lifted white chrome around each of the glance's two halves (streak,
/// rewards) — mockup `.panel`: a `surface` fill, a hairline border, the object
/// card radius, and the soft layered `cardShadow`. Clips its child so a reward
/// image can bleed to the panel edge. Content-agnostic; the panel decides only
/// the frame + its generous internal padding.
///
/// The same chrome carries the "Get the app" welcome panels, so [color] /
/// [borderColor] can override the fill for the accent-soft app card (mockup
/// `.app-card`) without a second panel widget.
class KioskGlancePanel extends StatelessWidget {
  final Widget child;

  /// Fill override — the "Get the app" card's soft accent wash. Defaults to
  /// the panel `surface`.
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
