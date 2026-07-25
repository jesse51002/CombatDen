import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';

/// The app card's three value props, sapphire-checked. Deliberately the same
/// three the showcase panel rotates through — the card states the promise,
/// the slideshow shows it.
class KioskAppBenefits extends StatelessWidget {
  const KioskAppBenefits({super.key});

  @override
  Widget build(BuildContext context) {
    return const Wrap(
      alignment: WrapAlignment.center,
      spacing: DesignConstants.spacingLarge,
      runSpacing: DesignConstants.spacingMedium,
      children: [
        _Benefit(label: 'Book classes'),
        _Benefit(label: 'Earn rewards'),
        _Benefit(label: 'Watch videos'),
      ],
    );
  }
}

class _Benefit extends StatelessWidget {
  final String label;

  const _Benefit({required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingSmall,
      children: [
        Icon(
          Symbols.check_sharp,
          size: DesignConstants.iconSizeTiny,
          weight: DesignConstants.iconWeight,
          color: DesignConstants.primaryColor,
        ),
        Text(label, style: DesignConstants.kioskCaption),
      ],
    );
  }
}
