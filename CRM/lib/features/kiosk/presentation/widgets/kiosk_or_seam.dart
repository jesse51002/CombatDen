import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';

/// The vertical "or" seam between the two home halves — a full-height hairline
/// rule with a small round "or" badge centered on it (mockup `.home-seam` /
/// `.seam-badge`). Vertical because the two halves sit side by side.
///
/// The rule is `Positioned.fill` (mirroring the mockup's absolutely-positioned
/// `::before`) so it fills whatever height the taller half sets without ever
/// claiming its own height — only the finite badge drives the seam's size, so
/// the parent's stretch/IntrinsicHeight resolve cleanly. The ground-colored
/// badge breaks the rule at its middle.
class KioskOrSeam extends StatelessWidget {
  const KioskOrSeam({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: DesignConstants.navMenuButtonSize,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: VerticalDivider(
              thickness: DesignConstants.dividerThickness,
              color: DesignConstants.line,
            ),
          ),
          const _Badge(),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: DesignConstants.navMenuButtonSize,
      height: DesignConstants.navMenuButtonSize,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: DesignConstants.backgroundColor,
        shape: BoxShape.circle,
        border: Border.all(color: DesignConstants.line),
      ),
      child: Text(
        'or',
        style: DesignConstants.kioskMicro.copyWith(
          color: DesignConstants.text2nd,
        ),
      ),
    );
  }
}
