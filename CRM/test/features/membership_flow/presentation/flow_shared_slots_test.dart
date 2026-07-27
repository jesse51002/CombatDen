import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crm/features/membership_flow/config/kiosk_flow_copy.dart';
import 'package:crm/features/membership_flow/config/membership_flow_scale.dart';
import 'package:crm/features/membership_flow/config/membership_flow_theme.dart';
import 'package:crm/features/membership_flow/config/staff_flow_copy.dart';
import 'package:crm/features/membership_flow/presentation/models/flow_money_view.dart';
import 'package:crm/features/membership_flow/presentation/widgets/flow_buy_row.dart';
import 'package:crm/features/membership_flow/presentation/widgets/flow_money_panel.dart';

/// Two shared components grew a slot for the desk. Both slots are OPTIONAL,
/// and that is the property under test: a surface with nothing to put in one
/// renders exactly what it rendered before, so the kiosk's tree is unchanged
/// by a capability it does not have.
///
/// This is the same shape as the discounts capability one layer down —
/// absent, never disabled — applied to a widget instead of a config.
void main() {
  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    bool staff = true,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MembershipFlowTheme(
            scale: staff
                ? const MembershipFlowScale.admin()
                : const MembershipFlowScale.kiosk(),
            copy: staff ? const StaffFlowCopy() : const KioskFlowCopy(),
            child: SingleChildScrollView(child: child),
          ),
        ),
      ),
    );
  }

  group('FlowBuyRow', () {
    testWidgets('an unreduced row is ONE figure, not a struck pair', (
      tester,
    ) async {
      await pump(
        tester,
        const FlowBuyRow(name: 'Unlimited Monthly', amount: '\$149.00'),
      );

      expect(find.text('\$149.00'), findsOneWidget);
      expect(find.byType(Text), findsNWidgets(2));
    });

    testWidgets('a reduced row carries BOTH figures', (tester) async {
      await pump(
        tester,
        const FlowBuyRow(
          name: 'Unlimited Monthly',
          amount: '\$104.20',
          struckAmount: '\$149.00',
        ),
      );

      // The list price stays on screen: a discount nobody can see is a
      // discount the member never hears about.
      expect(find.text('\$149.00'), findsOneWidget);
      expect(find.text('\$104.20'), findsOneWidget);
      final struck = tester.widget<Text>(find.text('\$149.00'));
      expect(struck.style?.decoration, TextDecoration.lineThrough);
    });
  });

  group('FlowMoneyPanel slots', () {
    const money = FlowMoneyView(
      dueTodayMinorUnits: 63553,
      currency: 'usd',
      lines: [FlowMoneyLine(label: '10-Class Pack', amountMinorUnits: 18000)],
      recurring: FlowRecurringView(
        totalMinorUnits: 10420,
        cycleWord: 'month',
      ),
    );

    testWidgets('a surface with no first-period choice renders none', (
      tester,
    ) async {
      await pump(
        tester,
        const FlowMoneyPanel(money: money, contactEmail: ''),
        staff: false,
      );

      expect(find.text('THE FIRST PERIOD'), findsNothing);
      expect(find.text('Marcus\'s total each month'), findsNothing);
    });

    testWidgets('the desk\'s two slots render where they are handed in', (
      tester,
    ) async {
      await pump(
        tester,
        const FlowMoneyPanel(
          money: money,
          contactEmail: '',
          firstPeriod: Text('THE FIRST PERIOD'),
          recurringBreakdown: Text('Marcus\'s total each month'),
        ),
      );

      expect(find.text('THE FIRST PERIOD'), findsOneWidget);
      expect(find.text('Marcus\'s total each month'), findsOneWidget);
      // Still the same panel: the total and the itemisation are untouched.
      expect(find.text('\$635.53'), findsOneWidget);
      expect(find.text('10-Class Pack'), findsOneWidget);
    });
  });
}
