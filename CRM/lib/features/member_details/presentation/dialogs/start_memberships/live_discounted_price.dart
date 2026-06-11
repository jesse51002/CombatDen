import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/utils/money.dart';
import 'package:crm/features/member_details/data/models/discount_response.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/membership_draft.dart';

/// A draft membership's live price readout: the plan price
/// alone, or — once discounts are added — the original
/// slashed out next to the UI-computed discounted price
/// (percents first, then dollars; the Preview step stays
/// the authoritative figure).
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
    if (!draft.hasDiscounts) {
      return Text(
        formatMinorUnits(base, currency: 'USD'),
        style: DesignConstants.h2,
      );
    }
    final discounted = draft.discountedPriceCents(presets);
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
          formatMinorUnits(discounted, currency: 'USD'),
          style: DesignConstants.h2,
        ),
      ],
    );
  }
}
