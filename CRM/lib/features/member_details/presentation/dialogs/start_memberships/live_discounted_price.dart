import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/utils/money.dart';
import 'package:crm/features/member_details/data/models/discount_response.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/membership_draft.dart';

/// A draft membership's live price readout: the plan price
/// alone, or — once discounts are added — the original
/// slashed out next to the UI-computed discounted price
/// (percents first, then dollars). When the quantity is > 1
/// (stacked one_time / trial packs) the headline is the TOTAL
/// with an `N × unit` breakdown below. The Preview step stays
/// the authoritative figure.
class LiveDiscountedPrice extends StatelessWidget {
  final MembershipDraft draft;
  final List<DiscountResponse> presets;

  const LiveDiscountedPrice({
    super.key,
    required this.draft,
    required this.presets,
  });

  @override
  Widget build(BuildContext context) {
    final base = draft.plan.activePrice?.price ?? 0;
    final hasDiscount = draft.hasDiscounts;
    final unit =
        hasDiscount ? draft.discountedPriceCents(presets) : base;
    final count = draft.count;

    if (count <= 1) {
      return _unitReadout(base, unit, hasDiscount);
    }

    // Stacked packs: TOTAL headline + `N × unit` breakdown.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingTiny,
      children: [
        Text(
          formatMinorUnits(unit * count, currency: 'USD'),
          style: DesignConstants.h2,
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          spacing: DesignConstants.spacingTiny,
          children: [
            Text(
              '$count × ',
              style: DesignConstants.pSmall.copyWith(
                color: DesignConstants.text2nd,
              ),
            ),
            if (hasDiscount)
              Text(
                formatMinorUnits(base, currency: 'USD'),
                style: DesignConstants.pSmall.copyWith(
                  color: DesignConstants.text3rd,
                  decoration: TextDecoration.lineThrough,
                  decorationColor: DesignConstants.text3rd,
                ),
              ),
            Text(
              formatMinorUnits(unit, currency: 'USD'),
              style: DesignConstants.pSmall.copyWith(
                color: DesignConstants.text2nd,
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// The single-unit price: the plan price, or the original
  /// slashed out next to the discounted price.
  Widget _unitReadout(int base, int unit, bool hasDiscount) {
    if (!hasDiscount) {
      return Text(
        formatMinorUnits(unit, currency: 'USD'),
        style: DesignConstants.h2,
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingSmall,
      children: [
        Text(
          formatMinorUnits(base, currency: 'USD'),
          style: DesignConstants.p.copyWith(
            color: DesignConstants.text2nd,
            decoration: TextDecoration.lineThrough,
            decorationColor: DesignConstants.text2nd,
          ),
        ),
        Text(
          formatMinorUnits(unit, currency: 'USD'),
          style: DesignConstants.h2,
        ),
      ],
    );
  }
}
