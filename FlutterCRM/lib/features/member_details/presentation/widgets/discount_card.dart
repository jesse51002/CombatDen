import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/discount_info.dart';

/// A card displaying a discount with icon, name, date
/// range, and discount badge.
class DiscountCard extends StatelessWidget {
  final DiscountInfo discount;

  const DiscountCard({
    super.key,
    required this.discount,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(
        DesignConstants.spacingSmall,
      ),
      decoration: BoxDecoration(
        color: DesignConstants.cardBackground,
        borderRadius: BorderRadius.circular(
          DesignConstants.radiusSmall,
        ),
      ),
      child: Row(
        children: [
          // Icon
          const Icon(
            Icons.card_giftcard,
            color: DesignConstants.goodGreen,
            size: 24,
          ),
          const SizedBox(
            width:
                DesignConstants.spacingSmall,
          ),
          // Name + date range
          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  discount.discountName,
                  style: DesignConstants.p,
                ),
                if (discount.startDate != null ||
                    discount.endDate != null)
                  Text(
                    _dateRange,
                    style: DesignConstants.pSmall.copyWith(
                      color: DesignConstants.text2nd,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          const SizedBox(
            width:
                DesignConstants.spacingSmall,
          ),
          // Discount badge
          if (discount.discountLabel.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal:
                    DesignConstants.spacingSmall,
                vertical:
                    DesignConstants.spacingTiny,
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
                discount.discountLabel,
                style: DesignConstants.pSmall.copyWith(
                  color: DesignConstants.goodGreen,
                ),
              ),
            ),
        ],
      ),
    );
  }

  String get _dateRange {
    final fmt = DateFormat('M/dd/yyyy');
    final parts = <String>[];
    if (discount.startDate != null) {
      parts.add(fmt.format(discount.startDate!.toLocal()));
    }
    if (discount.endDate != null) {
      parts.add(fmt.format(discount.endDate!.toLocal()));
    }
    return parts.join(' - ');
  }
}
