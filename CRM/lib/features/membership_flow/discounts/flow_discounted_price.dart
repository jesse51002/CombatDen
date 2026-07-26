import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/utils/money.dart';
import 'package:crm/features/member_details/data/models/discount_value.dart';
import 'package:crm/features/membership_flow/config/membership_flow_theme.dart';
import 'package:crm/features/membership_flow/discounts/discounts_capability.dart';

/// What one picked membership costs right now: the list price struck through
/// beside what it actually comes to, with the arithmetic underneath.
///
/// **Staff-only** — see `discount_labels.dart`.
///
/// **Every figure comes from `domain/discount_math.dart`**, through the
/// capability. Nothing here re-derives a price, because a second
/// implementation of "percents compound, then each fixed amount comes off once
/// per line" is exactly the drift that ends with a card and an invoice
/// disagreeing in front of a member.
///
/// It is an ESTIMATE and the step says so once, below the grid — the Preview
/// step's server figure is the authoritative one, and this is the live readout
/// while staff are still assembling the cart.
class FlowDiscountedPrice extends StatelessWidget {
  final DiscountsCapability discounts;

  /// The plan's own list price, per unit, in minor units.
  final int unitPriceCents;

  /// How many units of it — stacked one-time packs, or 1.
  final int units;

  final Set<String> presetIds;
  final List<DiscountValue> customs;

  /// The ISO code every figure renders in.
  final String currency;

  /// The line under the amount naming the billing cadence — `each month`,
  /// `once`. The plan's word, so a weekly plan never reads as monthly.
  final String? cadence;

  const FlowDiscountedPrice({
    super.key,
    required this.discounts,
    required this.unitPriceCents,
    required this.presetIds,
    required this.customs,
    this.units = 1,
    this.currency = 'usd',
    this.cadence,
  });

  @override
  Widget build(BuildContext context) {
    final scale = MembershipFlowTheme.of(context);
    final gross = unitPriceCents * units;
    final net = discounts.lineTotalCents(
      unitPriceCents: unitPriceCents,
      units: units,
      presetIds: presetIds,
      customs: customs,
    );
    final reduced = net < gross;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingTiny,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          spacing: DesignConstants.spacingSmall,
          children: [
            // The struck price stays BESIDE the real one rather than replacing
            // it: staff quote both, and a discount nobody can see is a
            // discount the member never hears about.
            if (reduced)
              Text(
                formatMinorUnits(gross, currency: currency),
                style: scale.caption.copyWith(
                  color: DesignConstants.text2nd,
                  decoration: TextDecoration.lineThrough,
                  decorationColor: DesignConstants.text2nd,
                ),
              ),
            Text(
              formatMinorUnits(net, currency: currency),
              style: scale.statement,
            ),
          ],
        ),
        _Detail(
          unitPriceCents: unitPriceCents,
          units: units,
          gross: gross,
          currency: currency,
          cadence: cadence,
        ),
      ],
    );
  }
}

/// The line under the amount: the cadence, and — once more than one unit is on
/// the line — the multiplication that produced the gross.
///
/// `3 × $180.00 = $540.00` is shown because a fixed-amount discount comes off
/// the LINE once rather than per unit, so there is no honest per-unit
/// discounted figure to print instead.
class _Detail extends StatelessWidget {
  final int unitPriceCents;
  final int units;
  final int gross;
  final String currency;
  final String? cadence;

  const _Detail({
    required this.unitPriceCents,
    required this.units,
    required this.gross,
    required this.currency,
    this.cadence,
  });

  @override
  Widget build(BuildContext context) {
    final scale = MembershipFlowTheme.of(context);
    final parts = <String>[
      if (units > 1)
        '$units × ${formatMinorUnits(unitPriceCents, currency: currency)} = '
            '${formatMinorUnits(gross, currency: currency)}',
      ?cadence,
    ];
    if (parts.isEmpty) return const SizedBox.shrink();
    return Text(
      parts.join(' · '),
      style: scale.caption.copyWith(color: DesignConstants.text2nd),
      textAlign: TextAlign.end,
    );
  }
}
