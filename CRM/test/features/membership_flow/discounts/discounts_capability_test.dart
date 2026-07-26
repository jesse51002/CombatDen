import 'package:flutter_test/flutter_test.dart';

import 'package:crm/features/member_details/data/models/discount_duration_unit.dart';
import 'package:crm/features/member_details/data/models/discount_response.dart';
import 'package:crm/features/member_details/data/models/discount_type.dart';
import 'package:crm/features/member_details/data/models/discount_value.dart';
import 'package:crm/features/membership_flow/discounts/discount_labels.dart';
import 'package:crm/features/membership_flow/discounts/discounts_capability.dart';
import 'package:crm/features/membership_flow/domain/discount_math.dart';

/// The capability object — what it offers, what it refuses to offer, and the
/// fact that it does no arithmetic of its own.
void main() {
  DiscountResponse preset({
    required String id,
    required String name,
    required DiscountValue value,
    DiscountType type = DiscountType.preset,
    bool deleted = false,
  }) =>
      DiscountResponse(
        discountId: id,
        gymId: 'gym',
        discountName: name,
        discountType: type,
        valueId: 'v-$id',
        value: value,
        isDeleted: deleted,
        createdAt: DateTime.utc(2026, 1, 1),
      );

  final family = preset(
    id: 'family',
    name: 'Family 20%',
    value: const DiscountValue(percentageOff: 20),
  );
  final founding = preset(
    id: 'founding',
    name: 'Founding member \$15 off',
    value: const DiscountValue(
      dollarOff: 1500,
      durationAmount: 3,
      durationUnit: DiscountDurationUnit.cycle,
    ),
  );

  group('what may be offered', () {
    test('a one-off CUSTOM row is never offered as a reusable preset', () {
      final capability = DiscountsCapability(
        presets: [
          family,
          preset(
            id: 'one-off',
            name: 'One-off',
            value: const DiscountValue(percentageOff: 50),
            type: DiscountType.custom,
          ),
        ],
      );
      expect(
        capability.offerablePresets.map((d) => d.discountId),
        ['family'],
        reason: 'it was minted for somebody else\'s membership',
      );
    });

    test('a soft-deleted preset drops out', () {
      final capability = DiscountsCapability(
        presets: [family, preset(id: 'gone', name: 'Gone', value: family.value,
            deleted: true)],
      );
      expect(capability.offerablePresets.map((d) => d.discountId), ['family']);
      expect(capability.hasOfferablePresets, isTrue);
    });

    test('a gym with nothing offerable says so', () {
      const capability = DiscountsCapability();
      expect(capability.offerablePresets, isEmpty);
      expect(capability.hasOfferablePresets, isFalse);
    });

    test('a preset can still be RESOLVED after it stops being offerable', () {
      // A preset deleted mid-run is still on the membership somebody already
      // added it to; dropping its value silently would change a price.
      final gone = preset(
        id: 'gone',
        name: 'Gone',
        value: const DiscountValue(percentageOff: 10),
        deleted: true,
      );
      final capability = DiscountsCapability(presets: [gone]);
      expect(capability.presetById('gone'), gone);
      expect(
        capability.valuesFor(presetIds: {'gone'}, customs: const []),
        [gone.value],
      );
    });
  });

  group('the figures come from the shared math, never from here', () {
    final capability = DiscountsCapability(presets: [family, founding]);

    test('a line total matches domain/discount_math.dart exactly', () {
      const customs = [DiscountValue(percentageOff: 10)];
      final expected = discountedLineTotalCents(
        unitPriceCents: 18000,
        units: 3,
        values: [family.value, founding.value, ...customs],
      );
      expect(
        capability.lineTotalCents(
          unitPriceCents: 18000,
          units: 3,
          presetIds: {'family', 'founding'},
          customs: customs,
        ),
        expected,
      );
    });

    test('percents compound on the LINE, then each dollar comes off once', () {
      // 3 × $180 = $540 → −20% = $432 → −$15 once = $417.
      expect(
        capability.lineTotalCents(
          unitPriceCents: 18000,
          units: 3,
          presetIds: {'family', 'founding'},
          customs: const [],
        ),
        41700,
      );
    });

    test('an unknown preset id drops out rather than throwing', () {
      expect(
        capability.lineTotalCents(
          unitPriceCents: 10000,
          units: 1,
          presetIds: {'nope'},
          customs: const [],
        ),
        10000,
      );
    });
  });

  group('the chips a membership renders', () {
    final capability = DiscountsCapability(presets: [family, founding]);

    test('a preset chip carries the gym\'s own name for it', () {
      final applied = capability.appliedFor(
        presetIds: {'family'},
        customs: const [],
      );
      expect(applied.single.label, 'Family 20%');
      expect(applied.single.reference, const FlowPresetDiscount('family'));
    });

    test('a custom chip says what it DOES — it has no name', () {
      final applied = capability.appliedFor(
        presetIds: const {},
        customs: const [
          DiscountValue(percentageOff: 12.5),
          DiscountValue(dollarOff: 1500),
        ],
      );
      expect(applied.map((d) => d.label), ['12.5% off', '\$15.00 off']);
      expect(
        applied.map((d) => d.reference),
        [const FlowCustomDiscount(0), const FlowCustomDiscount(1)],
        reason: 'removing the second of two identical customs must take the '
            'right one',
      );
    });

    test('presets come first, then customs, in pick order', () {
      final applied = capability.appliedFor(
        presetIds: {'family', 'founding'},
        customs: const [DiscountValue(percentageOff: 5)],
      );
      expect(
        applied.map((d) => d.label),
        ['Family 20%', 'Founding member \$15 off', '5% off'],
      );
    });

    test('a preset the catalogue no longer carries renders no chip', () {
      final applied = capability.appliedFor(
        presetIds: {'family', 'vanished'},
        customs: const [],
      );
      expect(applied.map((d) => d.label), ['Family 20%']);
    });
  });

  group('the lifetime label states the backend spec', () {
    test('neither field means forever', () {
      expect(flowDiscountLifetimeLabel(const DiscountValue()), 'Forever');
    });

    test('a cycle span reads in both cycles and months', () {
      expect(
        flowDiscountLifetimeLabel(founding.value),
        '3 cycles (3 months)',
      );
      expect(
        flowDiscountLifetimeLabel(
          const DiscountValue(
            durationAmount: 1,
            durationUnit: DiscountDurationUnit.cycle,
          ),
        ),
        '1 cycle (1 month)',
      );
    });

    test('a calendar span reads plainly', () {
      expect(
        flowDiscountLifetimeLabel(
          const DiscountValue(
            durationAmount: 30,
            durationUnit: DiscountDurationUnit.day,
          ),
        ),
        'For 30 days',
      );
    });

    test('an end date reads as a cutoff', () {
      expect(
        flowDiscountLifetimeLabel(
          DiscountValue(endDate: DateTime(2026, 11, 30)),
        ),
        'Until Nov 30, 2026',
      );
    });
  });

  test('the value label drops a trailing zero but keeps a real fraction', () {
    expect(
      flowDiscountValueLabel(const DiscountValue(percentageOff: 20)),
      '20% off',
    );
    expect(
      flowDiscountValueLabel(const DiscountValue(percentageOff: 12.5)),
      '12.5% off',
    );
    expect(
      flowDiscountValueLabel(const DiscountValue(dollarOff: 1500)),
      '\$15.00 off',
    );
  });
}
