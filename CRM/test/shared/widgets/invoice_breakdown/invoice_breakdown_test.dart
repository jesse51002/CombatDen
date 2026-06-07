import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crm/shared/widgets/invoice_breakdown/invoice_breakdown.dart';
import 'package:crm/shared/widgets/invoice_breakdown/invoice_breakdown_data.dart';

void main() {
  Future<void> pump(
    WidgetTester tester,
    InvoiceBreakdownData data,
  ) {
    return tester.pumpWidget(
      MaterialApp(
        // The M3 ink splash shader fails to decode in the test SDK;
        // unrelated to what we're testing.
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: Scaffold(body: InvoiceBreakdown(data: data)),
      ),
    );
  }

  testWidgets(
    'plain invoice renders a single amount, no comparison chrome',
    (tester) async {
      await pump(
        tester,
        const InvoiceBreakdownData(
          lines: [InvoiceLineItem(description: 'Boxing', amount: 9000)],
          total: 9000,
          currency: 'usd',
        ),
      );

      expect(tester.takeException(), isNull);
      // No before→after arrow and no Difference row on a plain invoice.
      expect(find.text('→'), findsNothing);
      expect(find.text('Difference'), findsNothing);
    },
  );

  testWidgets(
    'comparison invoice renders old→new, discount, and difference',
    (tester) async {
      await pump(
        tester,
        const InvoiceBreakdownData(
          lines: [
            InvoiceLineItem(
              description: 'Boxing  ×2',
              amount: 9000,
              discountAmount: -1800,
              previousAmount: 9000,
            ),
          ],
          total: 7200,
          currency: 'usd',
          previousTotal: 9000,
          totalLabel: 'Monthly',
          amountSuffix: '/mo',
        ),
      );

      expect(tester.takeException(), isNull);
      // Arrow on the line net row and the Monthly total row.
      expect(find.text('→'), findsWidgets);
      expect(find.text('Discount'), findsOneWidget);
      expect(find.text('Monthly'), findsOneWidget);
      // total - previousTotal = -1800 → "$18.00 less".
      expect(find.text('\$18.00 less'), findsOneWidget);
    },
  );
}
