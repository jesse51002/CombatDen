import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';

/// Semantic tone for an [InvoiceChip] — drives its color
/// off [DesignConstants] so callers never pick a raw color.
enum InvoiceChipTone { neutral, good, warning, bad, brand }

/// Small outlined pill used inside an invoice breakdown:
/// applied-discount tags and historical-charge status
/// labels both render through this one primitive so every
/// pill on a billing surface looks identical.
///
/// The member-detail billing dialogs map their own charge
/// status / discount models onto a [label] + [tone].
class InvoiceChip extends StatelessWidget {
  final String label;
  final InvoiceChipTone tone;

  const InvoiceChip({
    super.key,
    required this.label,
    this.tone = InvoiceChipTone.neutral,
  });

  Color get _color {
    switch (tone) {
      case InvoiceChipTone.good:
        return DesignConstants.goodGreen;
      case InvoiceChipTone.warning:
        return DesignConstants.okYellow;
      case InvoiceChipTone.bad:
        return DesignConstants.badRed;
      case InvoiceChipTone.brand:
        return DesignConstants.primaryColor;
      case InvoiceChipTone.neutral:
        return DesignConstants.text2nd;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _color;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignConstants.spacingSmall,
        vertical: DesignConstants.spacingTiny,
      ),
      decoration: BoxDecoration(
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(
          DesignConstants.radiusBig,
        ),
      ),
      child: Text(
        label,
        style: DesignConstants.pSmall.copyWith(color: color),
      ),
    );
  }
}
