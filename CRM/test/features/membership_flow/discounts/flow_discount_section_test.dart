import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crm/features/member_details/data/models/discount_duration_unit.dart';
import 'package:crm/features/member_details/data/models/discount_response.dart';
import 'package:crm/features/member_details/data/models/discount_type.dart';
import 'package:crm/features/member_details/data/models/discount_value.dart';
import 'package:crm/features/membership_flow/config/membership_flow_scale.dart';
import 'package:crm/features/membership_flow/config/membership_flow_theme.dart';
import 'package:crm/features/membership_flow/config/staff_flow_copy.dart';
import 'package:crm/features/membership_flow/discounts/discounts_capability.dart';
import 'package:crm/features/membership_flow/discounts/flow_custom_discount_form.dart';
import 'package:crm/features/membership_flow/discounts/flow_discount_panel.dart';
import 'package:crm/features/membership_flow/discounts/flow_discount_section.dart';
import 'package:crm/features/membership_flow/discounts/flow_discounted_price.dart';

/// The inline discount surface, driven.
///
/// The behaviours worth pinning are the ones the old wizard got wrong: the
/// panel opens IN PLACE rather than in a dialog, an already-added preset stays
/// visible and inert, validation only appears after a failed Add, and the
/// `end_date` lifetime — unreachable from any screen until now — actually
/// reaches the wire.
void main() {
  DiscountResponse preset({
    required String id,
    required String name,
    required DiscountValue value,
    DiscountType type = DiscountType.preset,
  }) =>
      DiscountResponse(
        discountId: id,
        gymId: 'gym',
        discountName: name,
        discountType: type,
        valueId: 'v-$id',
        value: value,
        createdAt: DateTime.utc(2026, 1, 1),
      );

  final family = preset(
    id: 'family',
    name: 'Family 20%',
    value: const DiscountValue(percentageOff: 20),
  );
  final founding = preset(
    id: 'founding',
    name: 'Founding member',
    value: const DiscountValue(
      dollarOff: 1500,
      durationAmount: 3,
      durationUnit: DiscountDurationUnit.cycle,
    ),
  );

  /// The desk surface, mounted the way its host will: one scale and one voice
  /// above everything.
  Future<void> pump(WidgetTester tester, Widget child) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MembershipFlowTheme(
            scale: const MembershipFlowScale.admin(),
            copy: const StaffFlowCopy(),
            child: SingleChildScrollView(child: child),
          ),
        ),
      ),
    );
  }

  group('the chip row', () {
    testWidgets('renders one removable chip per applied discount', (
      tester,
    ) async {
      final removed = <FlowDiscountReference>[];
      await pump(
        tester,
        FlowDiscountSection(
          discounts: DiscountsCapability(presets: [family, founding]),
          presetIds: const {'family'},
          customs: const [DiscountValue(percentageOff: 12.5)],
          onAddPreset: (_) {},
          onAddCustom: (_) {},
          onRemove: removed.add,
        ),
      );

      expect(find.text('Family 20%'), findsOneWidget);
      expect(find.text('12.5% off'), findsOneWidget);

      await tester.tap(
        find.bySemanticsLabel('Remove Family 20% from this membership'),
      );
      expect(removed, [const FlowPresetDiscount('family')]);
    });

    testWidgets('removing a custom names it by POSITION, not by value', (
      tester,
    ) async {
      final removed = <FlowDiscountReference>[];
      await pump(
        tester,
        FlowDiscountSection(
          discounts: const DiscountsCapability(),
          presetIds: const {},
          customs: const [
            DiscountValue(percentageOff: 10),
            DiscountValue(percentageOff: 10),
          ],
          onAddPreset: (_) {},
          onAddCustom: (_) {},
          onRemove: removed.add,
        ),
      );

      // Two identical labels: only the reference tells them apart.
      expect(find.text('10% off'), findsNWidgets(2));
      await tester.tap(
        find.bySemanticsLabel('Remove 10% off from this membership').last,
      );
      expect(removed, [const FlowCustomDiscount(1)]);
    });
  });

  group('the panel opens IN PLACE', () {
    testWidgets('Add discount unfolds the panel without a dialog', (
      tester,
    ) async {
      await pump(
        tester,
        FlowDiscountSection(
          discounts: DiscountsCapability(presets: [family, founding]),
          presetIds: const {},
          customs: const [],
          onAddPreset: (_) {},
          onAddCustom: (_) {},
          onRemove: (_) {},
        ),
      );

      expect(find.byType(FlowDiscountPanel), findsNothing);
      await tester.tap(find.text('Add discount').first);
      await tester.pumpAndSettle();

      expect(find.byType(FlowDiscountPanel), findsOneWidget);
      expect(
        find.byType(Dialog),
        findsNothing,
        reason: 'a dialog is what made discounts feel like a separate job',
      );
    });

    testWidgets('an already-added preset stays listed and inert', (
      tester,
    ) async {
      final added = <String>[];
      await pump(
        tester,
        FlowDiscountSection(
          discounts: DiscountsCapability(presets: [family, founding]),
          presetIds: const {'family'},
          customs: const [],
          onAddPreset: added.add,
          onAddCustom: (_) {},
          onRemove: (_) {},
        ),
      );
      await tester.tap(find.text('Add discount').first);
      await tester.pumpAndSettle();

      // Still on the list — a list that shortens as you pick from it makes
      // staff hunt for what they just chose.
      expect(find.text('Family 20%'), findsWidgets);
      expect(find.text('Added'), findsOneWidget);

      await tester.tap(find.text('Family 20%').last);
      await tester.pumpAndSettle();
      expect(added, isEmpty, reason: 'the added row does nothing on tap');

      await tester.tap(find.text('Founding member').last);
      await tester.pumpAndSettle();
      expect(added, ['founding']);
    });

    testWidgets('the lifetime is shown beside every preset\'s value', (
      tester,
    ) async {
      await pump(
        tester,
        FlowDiscountSection(
          discounts: DiscountsCapability(presets: [family, founding]),
          presetIds: const {},
          customs: const [],
          onAddPreset: (_) {},
          onAddCustom: (_) {},
          onRemove: (_) {},
        ),
      );
      await tester.tap(find.text('Add discount').first);
      await tester.pumpAndSettle();

      expect(find.text('Forever'), findsWidgets);
      expect(find.text('3 cycles (3 months)'), findsOneWidget);
      expect(find.text('20% off'), findsOneWidget);
      expect(find.text('\$15.00 off'), findsOneWidget);
    });

    testWidgets('a gym with no presets still gets the custom form', (
      tester,
    ) async {
      await pump(
        tester,
        FlowDiscountSection(
          discounts: const DiscountsCapability(),
          presetIds: const {},
          customs: const [],
          onAddPreset: (_) {},
          onAddCustom: (_) {},
          onRemove: (_) {},
        ),
      );
      await tester.tap(find.text('Add discount').first);
      await tester.pumpAndSettle();

      expect(find.byType(FlowCustomDiscountForm), findsOneWidget);

      // The presets tab still exists and still explains itself.
      await tester.tap(find.text('Gym discounts'));
      await tester.pumpAndSettle();
      expect(find.text('This gym has no discount presets.'), findsOneWidget);
    });
  });

  group('the custom form', () {
    Future<void> openCustom(WidgetTester tester,
        {required ValueChanged<DiscountValue> onAdd}) async {
      await pump(
        tester,
        FlowDiscountSection(
          discounts: DiscountsCapability(presets: [family]),
          presetIds: const {},
          customs: const [],
          onAddPreset: (_) {},
          onAddCustom: onAdd,
          onRemove: (_) {},
        ),
      );
      await tester.tap(find.text('Add discount').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Custom'));
      await tester.pumpAndSettle();
    }

    testWidgets('nothing is checked until Add is pressed', (tester) async {
      await openCustom(tester, onAdd: (_) {});
      await tester.enterText(find.byType(TextField).first, '120');
      await tester.pumpAndSettle();
      expect(find.text('Percent must be 1–100'), findsNothing);
    });

    testWidgets('an empty amount says what to type', (tester) async {
      final added = <DiscountValue>[];
      await openCustom(tester, onAdd: added.add);
      await tester.tap(find.widgetWithText(InkWell, 'Add discount').last);
      await tester.pumpAndSettle();

      expect(find.text('Enter an amount'), findsOneWidget);
      expect(added, isEmpty);
    });

    testWidgets('an out-of-range percent states its range', (tester) async {
      final added = <DiscountValue>[];
      await openCustom(tester, onAdd: added.add);
      await tester.enterText(find.byType(TextField).first, '120');
      await tester.tap(find.widgetWithText(InkWell, 'Add discount').last);
      await tester.pumpAndSettle();

      expect(find.text('Percent must be 1–100'), findsOneWidget);
      expect(added, isEmpty);
    });

    testWidgets('a zero dollar amount says it must be above 0', (
      tester,
    ) async {
      final added = <DiscountValue>[];
      await openCustom(tester, onAdd: added.add);
      await tester.tap(find.text('\$ off'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '0');
      await tester.tap(find.widgetWithText(InkWell, 'Add discount').last);
      await tester.pumpAndSettle();

      expect(find.text('Amount must be above 0'), findsOneWidget);
      expect(added, isEmpty);
    });

    testWidgets('a bad span count says a count is a number above 0', (
      tester,
    ) async {
      final added = <DiscountValue>[];
      await openCustom(tester, onAdd: added.add);
      await tester.enterText(find.byType(TextField).first, '20');
      await tester.tap(find.text('Cycles'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, '0');
      await tester.tap(find.widgetWithText(InkWell, 'Add discount').last);
      await tester.pumpAndSettle();

      expect(find.text('Enter a number above 0'), findsOneWidget);
      expect(added, isEmpty);
    });

    testWidgets('a fixed error clears the moment the answer moves', (
      tester,
    ) async {
      await openCustom(tester, onAdd: (_) {});
      await tester.tap(find.widgetWithText(InkWell, 'Add discount').last);
      await tester.pumpAndSettle();
      expect(find.text('Enter an amount'), findsOneWidget);

      await tester.tap(find.text('\$ off'));
      await tester.pumpAndSettle();
      expect(find.text('Enter an amount'), findsNothing);
    });

    testWidgets('the cycle count reads in months too, live', (tester) async {
      await openCustom(tester, onAdd: (_) {});
      await tester.tap(find.text('Cycles'));
      await tester.pumpAndSettle();
      expect(find.text('1 cycle (1 month)'), findsOneWidget);

      await tester.enterText(find.byType(TextField).last, '3');
      await tester.pumpAndSettle();
      expect(find.text('3 cycles (3 months)'), findsOneWidget);
    });

    testWidgets('a forever percent reaches the caller as a bare value', (
      tester,
    ) async {
      final added = <DiscountValue>[];
      await openCustom(tester, onAdd: added.add);
      await tester.enterText(find.byType(TextField).first, '12.5');
      await tester.tap(find.widgetWithText(InkWell, 'Add discount').last);
      await tester.pumpAndSettle();

      expect(added, hasLength(1));
      expect(added.single.percentageOff, 12.5);
      expect(added.single.durationUnit, isNull);
      expect(added.single.endDate, isNull);
    });

    testWidgets('UNTIL A DATE is offered, and sends an end_date', (
      tester,
    ) async {
      final added = <DiscountValue>[];
      await openCustom(tester, onAdd: added.add);
      await tester.enterText(find.byType(TextField).first, '20');
      await tester.pumpAndSettle();

      // The lifetime the wizard could never express.
      expect(find.text('Until a date'), findsOneWidget);
      await tester.tap(find.text('Until a date'));
      await tester.pumpAndSettle();

      // It opens with a real date already in it, so there is no fifth
      // validation message for a missing one.
      expect(find.text('Last day it applies'), findsOneWidget);
      expect(find.text('How many cycles'), findsNothing);

      await tester.tap(find.widgetWithText(InkWell, 'Add discount').last);
      await tester.pumpAndSettle();

      expect(added, hasLength(1));
      expect(added.single.percentageOff, 20);
      expect(added.single.endDate, isNotNull);
      expect(
        added.single.durationAmount,
        isNull,
        reason: 'a span and an end date are exclusive',
      );
      expect(added.single.durationUnit, isNull);
    });

    testWidgets('adding a custom folds the panel away', (tester) async {
      await openCustom(tester, onAdd: (_) {});
      await tester.enterText(find.byType(TextField).first, '20');
      await tester.tap(find.widgetWithText(InkWell, 'Add discount').last);
      await tester.pumpAndSettle();

      expect(find.byType(FlowDiscountPanel), findsNothing);
    });

    testWidgets('Cancel folds it away without adding anything', (
      tester,
    ) async {
      final added = <DiscountValue>[];
      await openCustom(tester, onAdd: added.add);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.byType(FlowDiscountPanel), findsNothing);
      expect(added, isEmpty);
    });
  });

  group('the live price', () {
    testWidgets('shows the list price struck through beside the real one', (
      tester,
    ) async {
      await pump(
        tester,
        FlowDiscountedPrice(
          discounts: DiscountsCapability(presets: [family, founding]),
          unitPriceCents: 18000,
          units: 3,
          presetIds: const {'family', 'founding'},
          customs: const [],
          cadence: 'once',
        ),
      );

      // 3 × $180 = $540 → −20% = $432 → −$15 once = $417.
      expect(find.text('\$540.00'), findsOneWidget);
      expect(find.text('\$417.00'), findsOneWidget);
      expect(find.text('3 × \$180.00 = \$540.00 · once'), findsOneWidget);
    });

    testWidgets('an undiscounted line shows one figure, not a struck pair', (
      tester,
    ) async {
      await pump(
        tester,
        const FlowDiscountedPrice(
          discounts: DiscountsCapability(),
          unitPriceCents: 14900,
          presetIds: {},
          customs: [],
          cadence: 'each month',
        ),
      );

      expect(find.text('\$149.00'), findsOneWidget);
      expect(find.text('each month'), findsOneWidget);
    });
  });
}
