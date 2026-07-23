import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';

/// The "or" seam between the two home halves — a hairline rule with a small
/// round "or" badge centered on it (mockup `.home-seam` / `.seam-badge`).
/// Horizontal here because the two halves stack vertically on the iPad.
class KioskOrSeam extends StatelessWidget {
  const KioskOrSeam({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      spacing: DesignConstants.spacingLarge,
      children: [
        const Expanded(child: _Rule()),
        const _Badge(),
        const Expanded(child: _Rule()),
      ],
    );
  }
}

class _Rule extends StatelessWidget {
  const _Rule();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: DesignConstants.dividerThickness,
      color: DesignConstants.line,
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
        style: DesignConstants.pSmall.copyWith(
          color: DesignConstants.text3rd,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
