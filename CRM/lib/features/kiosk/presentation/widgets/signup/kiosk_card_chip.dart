import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';

/// "VISA · Card ending 4242" — the only card facts the kiosk ever holds,
/// shown wherever the member needs to know WHICH card is about to be (or has
/// just been) charged: the review, the paying lock and the decline.
///
/// The brand arrives from Stripe lowercase, so it is upper-cased for display
/// the way every other backend string on this app is capitalized before it is
/// shown. With no brand known the chip carries a plain card glyph instead —
/// never a stand-in brand.
class KioskCardChip extends StatelessWidget {
  final String? brand;
  final String? last4;

  const KioskCardChip({super.key, this.brand, this.last4});

  @override
  Widget build(BuildContext context) {
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
              style: DesignConstants.kioskEyebrow,
            ),
          Text(
            digits == null || digits.isEmpty
                ? 'Card on file'
                : 'Card ending $digits',
            style: DesignConstants.kioskCaption.copyWith(
              color: DesignConstants.text2nd,
            ),
          ),
        ],
      ),
    );
  }
}
