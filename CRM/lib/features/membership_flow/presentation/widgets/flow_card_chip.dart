import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/membership_flow/config/membership_flow_theme.dart';

/// "VISA · Card ending 4242" — the only card facts the kiosk ever holds, shown
/// wherever the member needs to know WHICH card is about to be (or has just
/// been) charged: the review, the paying lock and the decline.
///
/// With no brand known the chip carries a plain card glyph — never a stand-in
/// brand.
class FlowCardChip extends StatelessWidget {
  final String? brand;
  final String? last4;

  const FlowCardChip({super.key, this.brand, this.last4});

  @override
  Widget build(BuildContext context) {
    final scale = MembershipFlowTheme.of(context);
    final label = brand?.trim();
    final digits = last4?.trim();
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignConstants.spacingMedium,
        vertical: DesignConstants.spacingSmall,
      ),
      decoration: BoxDecoration(
        color: DesignConstants.card,
        borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
        border: Border.all(color: DesignConstants.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: DesignConstants.spacingMedium,
        children: [
          if (label == null || label.isEmpty)
            Icon(
              Symbols.credit_card_sharp,
              size: DesignConstants.iconSizeSmall,
              weight: DesignConstants.iconWeight,
              color: DesignConstants.text2nd,
            )
          else
            Text(
              label.toUpperCase(),
              style: scale.eyebrow,
            ),
          Text(
            digits == null || digits.isEmpty
                ? 'Card on file'
                : 'Card ending $digits',
            style: scale.caption.copyWith(
              color: DesignConstants.text2nd,
            ),
          ),
        ],
      ),
    );
  }
}
