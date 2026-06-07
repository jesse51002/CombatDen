import 'package:flutter_test/flutter_test.dart';

import 'package:crm/features/member_details/data/models/payments_invoice_preview.dart';
import 'package:crm/features/member_details/presentation/widgets/invoice_preview_format.dart';

void main() {
  group('comparisonBreakdownFromPair', () {
    test('emits list price, discount, line net, and monthly diff', () {
      const current = PreviewInvoice(
        amountDue: 9000,
        subtotal: 9000,
        total: 9000,
        currency: 'usd',
        lines: [
          PreviewInvoiceLine(
            amount: 9000,
            discountedAmount: 9000,
            description: 'Boxing',
            quantity: 2,
            stripeSubscriptionItemId: 'si_1',
          ),
        ],
      );
      const next = PreviewInvoice(
        amountDue: 7200,
        subtotal: 9000,
        total: 7200,
        currency: 'usd',
        lines: [
          PreviewInvoiceLine(
            amount: 9000,
            discountedAmount: 7200,
            description: 'Boxing',
            quantity: 2,
            stripeSubscriptionItemId: 'si_1',
          ),
        ],
      );

      final data = comparisonBreakdownFromPair(
        current: current,
        next: next,
      );

      final line = data.lines.single;
      expect(line.description, 'Boxing  ×2');
      expect(line.amount, 9000); // undiscounted list price
      expect(line.discountAmount, -1800); // net - list
      expect(line.previousAmount, 9000); // current net
      expect(data.total, 7200);
      expect(data.previousTotal, 9000); // current total
      expect(data.totalLabel, 'Monthly');
      expect(data.amountSuffix, '/mo');
    });

    test('falls back to list price + fallback monthly with no current', () {
      const next = PreviewInvoice(
        amountDue: 7200,
        subtotal: 9000,
        total: 7200,
        currency: 'usd',
        lines: [
          PreviewInvoiceLine(
            amount: 9000,
            discountedAmount: 7200,
            description: 'Boxing',
            stripeSubscriptionItemId: 'si_2',
          ),
        ],
      );

      final data = comparisonBreakdownFromPair(
        current: null,
        next: next,
        fallbackCurrentMonthly: 5000,
      );

      // No matching current line → previous net falls back to list.
      expect(data.lines.single.previousAmount, 9000);
      expect(data.previousTotal, 5000); // fallback monthly
    });

    test('unchanged line: null discount and no ×N for quantity 1', () {
      const line = PreviewInvoiceLine(
        amount: 9000,
        discountedAmount: 9000,
        description: 'Boxing',
        quantity: 1,
        stripeSubscriptionItemId: 'si_1',
      );
      const current = PreviewInvoice(
        amountDue: 9000,
        subtotal: 9000,
        total: 9000,
        currency: 'usd',
        lines: [line],
      );
      const next = PreviewInvoice(
        amountDue: 9000,
        subtotal: 9000,
        total: 9000,
        currency: 'usd',
        lines: [line],
      );

      final data = comparisonBreakdownFromPair(
        current: current,
        next: next,
      );

      final out = data.lines.single;
      expect(out.discountAmount, isNull);
      expect(out.description, 'Boxing'); // quantity 1 → no ×N
      expect(out.previousAmount, 9000);
      expect(out.amount, 9000);
    });
  });

  group('previewInvoiceBreakdown', () {
    test('emits list price + per-line discount, reconciling to total', () {
      // Stripe returns line.amount pre-discount and folds the coupon
      // into discount_amounts; subtotal comes back already post-discount.
      const preview = PreviewInvoice(
        amountDue: 7200,
        subtotal: 7200,
        total: 7200,
        currency: 'usd',
        lines: [
          PreviewInvoiceLine(
            amount: 9000,
            discountedAmount: 7200,
            description: '3 × Premium',
          ),
        ],
      );

      final data = previewInvoiceBreakdown(preview, amountSuffix: '/mo');

      final line = data.lines.single;
      expect(line.amount, 9000); // undiscounted list price
      expect(line.discountAmount, -1800); // discountedAmount - amount
      expect(line.previousAmount, isNull); // plain, no before/after
      expect(data.subtotal, isNull); // discount line bridges to total
      expect(data.total, 7200);
      // list + discount reconciles to the post-discount total.
      expect(line.amount + line.discountAmount!, data.total);
      expect(data.amountSuffix, '/mo');
    });

    test('no discount row when the net equals the list price', () {
      const preview = PreviewInvoice(
        amountDue: 9000,
        subtotal: 9000,
        total: 9000,
        currency: 'usd',
        lines: [
          PreviewInvoiceLine(
            amount: 9000,
            discountedAmount: 9000,
            description: 'Boxing',
          ),
        ],
      );

      final data = previewInvoiceBreakdown(preview);

      expect(data.lines.single.discountAmount, isNull);
      expect(data.subtotal, isNull);
    });
  });
}
