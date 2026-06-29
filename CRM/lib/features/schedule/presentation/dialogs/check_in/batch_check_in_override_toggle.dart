import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';

/// The "Check in anyway" override toggle on the batch check-in picker — maps to
/// `allow_override`, forcing every picked member past the eligibility,
/// punch-card, and room-capacity gates (front-desk coverage for retroactive /
/// over-capacity / depleted check-ins).
class BatchCheckInOverrideToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const BatchCheckInOverrideToggle({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: DesignConstants.spacingSmall,
        children: [
          Icon(
            value
                ? Symbols.check_box_sharp
                : Symbols.check_box_outline_blank_sharp,
            size: DesignConstants.iconSizeLarge,
            weight: DesignConstants.iconWeight,
            color: value
                ? DesignConstants.primaryColor
                : DesignConstants.text2nd,
          ),
          Expanded(
            child: Text(
              'Check in anyway — force past eligibility, punch-card, and '
              'capacity limits (front-desk coverage).',
              style: DesignConstants.pSmall.copyWith(
                color: DesignConstants.text2nd,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
