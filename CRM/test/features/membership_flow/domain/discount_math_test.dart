import 'package:flutter_test/flutter_test.dart';

import 'package:crm/features/member_details/data/models/discount_response.dart';
import 'package:crm/features/member_details/data/models/discount_type.dart';
import 'package:crm/features/member_details/data/models/discount_value.dart';
import 'package:crm/features/membership_flow/domain/discount_math.dart';

/// **The UI's estimate must agree with the invoice the backend will cut.**
///
/// Stripe applies a fixed-$ coupon ONCE to a quantity-N line and a percent to
/// unit×N, so the line math is: percents compound sequentially over the whole
/// line base, THEN dollar amounts subtract once each, floored at zero. Getting
/// the order or the per-unit/per-line split wrong quotes staff a number the
/// Preview step then contradicts.
void main() {
  DiscountValue percent(double off) => DiscountValue(percentageOff: off);
  DiscountValue dollars(int centsOff) => DiscountValue(dollarOff: centsOff);

  DiscountResponse preset(String id, DiscountValue value) => DiscountResponse(
        discountId: id,
        gymId: 'gym-1',
        discountName: id,
        discountType: DiscountType.preset,
        valueId: 'value-$id',
        value: value,
        createdAt: DateTime.utc(2026, 1, 1),
      );

  group('discountedLineTotalCents', () {
    test('no values leaves the line at its gross', () {
      expect(
        discountedLineTotalCents(
          unitPriceCents: 10000,
          units: 3,
          values: const [],
        ),
        30000,
      );
    });

    test('percents compound SEQUENTIALLY, not additively', () {
      // 50% then 50% is 25% of the base, not free.
      expect(
        discountedLineTotalCents(
          unitPriceCents: 10000,
          units: 1,
          values: [percent(50), percent(50)],
        ),
        2500,
      );
    });

    test('a percent applies to the whole line (unit × N)', () {
      expect(
        discountedLineTotalCents(
          unitPriceCents: 10000,
          units: 3,
          values: [percent(10)],
        ),
        27000,
      );
    });

    test('a fixed-\$ amount subtracts ONCE per line, never per unit', () {
      // The whole point of the quantity-N Stripe line: $20 off a 3-pack is
      // $20, not $60.
      expect(
        discountedLineTotalCents(
          unitPriceCents: 10000,
          units: 3,
          values: [dollars(2000)],
        ),
        28000,
      );
    });

    test('percents run BEFORE dollars', () {
      // 10% off $100 = $90, then $20 off = $70. The other order gives $72.
      expect(
        discountedLineTotalCents(
          unitPriceCents: 10000,
          units: 1,
          values: [dollars(2000), percent(10)],
        ),
        7000,
      );
    });

    test('the line floors at zero — a discount never pays the member', () {
      expect(
        discountedLineTotalCents(
          unitPriceCents: 5000,
          units: 1,
          values: [dollars(9900)],
        ),
        0,
      );
    });
  });

  group('resolvedDiscountValues', () {
    test('presets resolve first, then the inline customs', () {
      final values = resolvedDiscountValues(
        presetIds: {'summer'},
        presets: [preset('summer', percent(10)), preset('other', percent(90))],
        customs: [dollars(500)],
      );

      expect(values.length, 2);
      expect(values.first.percentageOff, 10);
      expect(values.last.dollarOff, 500);
    });

    test('an id matching no preset drops out rather than throwing', () {
      // A preset archived between the picker and the readout must not crash
      // the step staff are standing on.
      expect(
        resolvedDiscountValues(
          presetIds: {'gone'},
          presets: [preset('summer', percent(10))],
          customs: const [],
        ),
        isEmpty,
      );
    });
  });
}
