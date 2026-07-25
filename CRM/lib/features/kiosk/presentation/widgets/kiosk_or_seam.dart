import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';

/// The vertical "or" seam between the two home halves — a full-height hairline
/// with a small round "or" badge breaking it at the middle. The rule is
/// `Positioned.fill` so it claims no height of its own; only the finite badge
/// drives the seam's size, which is what lets the parent's IntrinsicHeight
/// resolve.
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
