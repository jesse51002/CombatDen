import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/discount_info.dart';

/// Green pill that advertises an applied discount on an
/// invoice. Matches the chip style used in
/// `DiscountsSection`.
class DiscountChip extends StatelessWidget {
  final DiscountInfo discount;

  const DiscountChip({super.key, required this.discount});

  @override
  Widget build(BuildContext context) {
    final label = discount.discountLabel.isEmpty
        ? discount.discountName
        : '${discount.discountName} · ${discount.discountLabel}';
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignConstants.spacingSmall,
        vertical: DesignConstants.spacingTiny,
      ),
      decoration: BoxDecoration(
        border: Border.all(
          color: DesignConstants.goodGreen,
        ),
        borderRadius: BorderRadius.circular(
          DesignConstants.radiusBig,
        ),
      ),
      child: Text(
        label,
        style: DesignConstants.pSmall.copyWith(
          color: DesignConstants.goodGreen,
        ),
      ),
    );
  }
}
