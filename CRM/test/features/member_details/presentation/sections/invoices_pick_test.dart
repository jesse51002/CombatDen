import 'package:flutter_test/flutter_test.dart';

import 'package:crm/features/member_details/data/models/payments_invoice_preview.dart';
import 'package:crm/features/member_details/data/models/payments_invoice_response.dart';
import 'package:crm/features/member_details/presentation/sections/invoices_pick.dart';

/// The card confirms an amount and then hands the settle to the backend,
/// which independently re-resolves "the open invoice" as the newest OPEN
/// invoice on the payer's SUBSCRIPTION. If this picker looked at the
/// customer-wide list instead, the card could confirm $30 (an ad-hoc
/// invoice) while the backend charged $120 — and then report that the $30
/// was collected. These tests pin the two sides to the same invoice.
PaymentsInvoiceResponse _invoice({
  required String id,
  required int amount,
  String? subscriptionId = 'sub_1',
  String status = 'open',
  int created = 1000,
}) {
  return PaymentsInvoiceResponse(
    stripeInvoiceId: id,
    stripeSubscriptionId: subscriptionId,
    amountDue: amount,
    amountPaid: 0,
    amountRemaining: amount,
    currency: 'usd',
    status: status,
    created: created,
  );
}

void main() {
  group('pickPayerInvoice', () {
    test('ignores a non-subscription invoice even when it is newer', () {
      // The exact mismatch: a newer one-off invoice would have been shown
      // while the backend charged the subscription's.
      final picked = pickPayerInvoice(
        [
          _invoice(id: 'in_adhoc', amount: 3000,
              subscriptionId: null, created: 2000),
          _invoice(id: 'in_sub', amount: 12000, created: 1000),
        ],
        null,
        null,
      );

      expect(picked, isNotNull);
      expect(picked!.amount, 12000,
          reason: 'must show the SUBSCRIPTION invoice, not the ad-hoc one');
      expect(picked.hasBacklog, isFalse);
    });

    test('picks the newest open subscription invoice', () {
      final picked = pickPayerInvoice(
        [
          _invoice(id: 'in_old', amount: 100, created: 1000),
          _invoice(id: 'in_new', amount: 200, created: 3000),
          _invoice(id: 'in_mid', amount: 150, created: 2000),
        ],
        null,
        null,
      );

      expect(picked!.amount, 200, reason: 'newest wins, matching the backend');
    });

    test('reports a stacked backlog with the full outstanding total', () {
      final picked = pickPayerInvoice(
        [
          _invoice(id: 'in_1', amount: 12000, created: 3000),
          _invoice(id: 'in_2', amount: 12000, created: 2000),
          _invoice(id: 'in_3', amount: 12000, created: 1000),
        ],
        null,
        null,
      );

      expect(picked!.hasBacklog, isTrue);
      expect(picked.openCount, 3);
      expect(picked.openTotal, 36000, reason: 'the whole debt, not just one');
      expect(picked.amount, 12000, reason: 'a settle pays only the newest');
    });

    test('a single open invoice is not a backlog', () {
      final picked = pickPayerInvoice(
        [_invoice(id: 'in_1', amount: 12000)],
        null,
        null,
      );

      expect(picked!.hasBacklog, isFalse);
      expect(picked.openCount, 1);
    });

    test('ignores invoices that are not open', () {
      final picked = pickPayerInvoice(
        [
          _invoice(id: 'in_paid', amount: 12000, status: 'paid'),
          _invoice(id: 'in_draft', amount: 9000, status: 'draft'),
        ],
        null,
        null,
      );

      expect(picked, isNull, reason: 'nothing open -> no overdue card');
    });

    test('falls back to the upcoming invoice when nothing is open', () {
      // A paid subscription invoice must not suppress the upcoming preview.
      final due = DateTime(2026, 8, 1);
      final picked = pickPayerInvoice(
        [_invoice(id: 'in_paid', amount: 12000, status: 'paid')],
        const PreviewInvoice(
          amountDue: 5000,
          subtotal: 5000,
          total: 5000,
          currency: 'usd',
        ),
        due,
      );

      expect(picked, isNotNull);
      expect(picked!.overdue, isFalse);
      expect(picked.amount, 5000);
      expect(picked.date, due);
      expect(picked.hasBacklog, isFalse,
          reason: 'an upcoming invoice is not a backlog');
    });
  });
}
