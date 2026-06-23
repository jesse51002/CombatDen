import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/utils/money.dart';
import 'package:crm/features/member_details/data/models/discount_response.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/membership_draft.dart';

/// A draft membership's live price readout: the plan price
/// alone, or — once discounts are added — the original
/// slashed out next to the UI-computed discounted price
/// (percents first, then dollars). When the quantity is > 1
/// (stacked one_time / trial packs) the headline is the net
/// line TOTAL, with a `N × unit = gross` line and the
/// line-level `− $X off` below (a fixed-$ discount applies
/// ONCE to the whole line, matching the backend's quantity-N
/// Stripe line — not per unit). The Preview step stays the
/// authoritative figure.
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
    final count = draft.count;
    // The LINE total: percents on the whole line, fixed-$ subtracted
    // ONCE (matching the backend's quantity-N Stripe line). At count
    // 1 this is the discounted unit price.
    final net = hasDiscount
        ? draft.discountedLineTotalCents(presets, count)
        : base * count;

    if (count <= 1) {
      return _unitReadout(base, net, hasDiscount);
    }

    // Stacked packs: net TOTAL headline, the gross `N × unit = gross`
    // line, and the line-level discount (the fixed-$ applies once, so
    // there is no clean per-unit discounted figure to show).
    final gross = base * count;
    final unitStr = formatMinorUnits(base, currency: 'USD');
    final grossStr = formatMinorUnits(gross, currency: 'USD');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingTiny,
      children: [
        Text(
          formatMinorUnits(net, currency: 'USD'),
          style: DesignConstants.h2,
        ),
        Text(
          '$count × $unitStr = $grossStr',
          style: DesignConstants.pSmall.copyWith(
            color: DesignConstants.text2nd,
          ),
        ),
        if (hasDiscount && gross > net)
          Text(
            '− ${formatMinorUnits(gross - net, currency: 'USD')} off',
            style: DesignConstants.pSmall.copyWith(
              color: DesignConstants.text2nd,
            ),
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
