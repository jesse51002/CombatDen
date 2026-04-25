import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/discount_response.dart';
import 'package:crm/features/member_details/data/models/stripe_coupon_duration.dart';

/// 2-column grid of selectable discount tiles. Works for
/// single- and multi-select — callers drive selection via
/// [selectedIds] and handle toggling in [onTap].
class DiscountGrid extends StatelessWidget {
  final List<DiscountResponse> discounts;
  final Set<String> selectedIds;
  final ValueChanged<DiscountResponse> onTap;

  const DiscountGrid({
    super.key,
    required this.discounts,
    required this.selectedIds,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: DesignConstants.spacingMedium,
      mainAxisSpacing: DesignConstants.spacingMedium,
      childAspectRatio: 2.0,
      children: discounts
          .map(
            (d) => DiscountTile(
              discount: d,
              isSelected:
                  selectedIds.contains(d.discountId),
              onTap: () => onTap(d),
            ),
          )
          .toList(),
    );
  }
}

class DiscountTile extends StatelessWidget {
  final DiscountResponse discount;
  final bool isSelected;
  final VoidCallback onTap;

  const DiscountTile({
    super.key,
    required this.discount,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(
        DesignConstants.radiusSmall,
      ),
      child: Container(
        padding: const EdgeInsets.all(
          DesignConstants.spacingMedium,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? DesignConstants.primaryColor.withValues(
                  alpha: 0.1,
                )
              : DesignConstants.backgroundColor,
          borderRadius: BorderRadius.circular(
            DesignConstants.radiusSmall,
          ),
          border: Border.all(
            color: isSelected
                ? DesignConstants.primaryColor
                : DesignConstants.divider,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          spacing: DesignConstants.spacingMedium,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                spacing: DesignConstants.spacingTiny,
                children: [
                  Text(
                    discount.discountName,
                    style: DesignConstants.p.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    discount.displayLabel,
                    style: DesignConstants.pSmall.copyWith(
                      color: DesignConstants.text2nd,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    discountDurationLabel(discount),
                    style: DesignConstants.pSmall.copyWith(
                      color: DesignConstants.text3rd,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(
              isSelected
                  ? Symbols.check_circle_sharp
                  : Symbols.radio_button_unchecked_sharp,
              color: isSelected
                  ? DesignConstants.primaryColor
                  : DesignConstants.text3rd,
              weight: DesignConstants.iconWeight,
            ),
          ],
        ),
      ),
    );
  }
}

String discountDurationLabel(DiscountResponse d) {
  switch (d.duration) {
    case StripeCouponDuration.once:
      return 'Once';
    case StripeCouponDuration.repeating:
      final n = d.durationInMonths;
      if (n == null) return 'Repeating';
      return n == 1 ? 'For 1 month' : 'For $n months';
    case StripeCouponDuration.forever:
      return 'Forever';
    case StripeCouponDuration.unknown:
      return '—';
  }
}
