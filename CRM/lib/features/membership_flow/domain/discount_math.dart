/// The UI's estimate of a discounted membership line.
///
/// **Staff-only.** The kiosk has no vocabulary for reducing a price and must
/// never import this module — `test/features/kiosk/kiosk_forbidden_imports_test.dart`
/// is what enforces that, and it is structural rather than a flag.
///
/// The Preview step stays the authoritative figure; this is the live readout
/// while a staff member is still assembling the cart.
library;

import 'package:crm/features/member_details/data/models/discount_response.dart';
import 'package:crm/features/member_details/data/models/discount_value.dart';

/// The values a membership's picked preset ids and inline customs resolve to,
/// presets first, in pick order. An id matching no preset drops out.
List<DiscountValue> resolvedDiscountValues({
  required Set<String> presetIds,
  required List<DiscountResponse> presets,
  required List<DiscountValue> customs,
}) =>
    <DiscountValue>[
      for (final id in presetIds)
        for (final d in presets)
          if (d.discountId == id) d.value,
      ...customs,
    ];

/// One membership's LINE total after [values], in cents: percents apply first
/// to the line base ([units] × [unitPriceCents], compounding sequentially),
/// then dollar amounts subtract **once** from the line — mirroring the
/// backend's quantity-N Stripe line, where a fixed-$ coupon applies once to the
/// whole line (not per unit) and a percent applies to unit×N. Floored at zero,
/// percent→dollar order.
int discountedLineTotalCents({
  required int unitPriceCents,
  required int units,
  required List<DiscountValue> values,
}) {
  var price = (unitPriceCents * units).toDouble();
  for (final v in values) {
    final pct = v.percentageOff;
    if (pct != null) price *= 1 - pct / 100;
  }
  var cents = price.round();
  for (final v in values) {
    final dollars = v.dollarOff;
    if (dollars != null) cents -= dollars;
  }
  return cents < 0 ? 0 : cents;
}
