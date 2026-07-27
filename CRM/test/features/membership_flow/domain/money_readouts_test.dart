import 'package:flutter_test/flutter_test.dart';

import 'package:crm/features/member_details/data/models/member_memberships_start_preview.dart';
import 'package:crm/features/member_details/data/models/payments_invoice_preview.dart';
import 'package:crm/features/member_details/data/models/proration_behavior.dart';
import 'package:crm/features/membership_flow/domain/money_readouts.dart';

/// **What the member is told they are paying today.**
///
/// The preview is ALWAYS fetched at `prorate_to_anchor`, so `preview.dueNow`
/// carries the proration whatever the surface chose. A surface that offers
/// `no_charge` must therefore suppress that half locally — otherwise it would
/// read a charge back to staff that will never be made.
///
/// The kiosk pins `prorate_to_anchor` and its numbers are unchanged by the
/// extraction; the `no_charge` cases below are what makes the same functions
/// safe for the desk, which does offer the choice.
void main() {
  PreviewInvoice invoice({
    required int total,
    String currency = 'usd',
    bool proration = false,
    int? nextPaymentDate,
  }) =>
      PreviewInvoice(
        amountDue: total,
        subtotal: total,
        total: total,
        currency: currency,
        nextPaymentDate: nextPaymentDate,
        lines: [
          PreviewInvoiceLine(
            amount: total,
            discountedAmount: total,
            isProration: proration,
          ),
        ],
      );

  const prorate = ProrationBehavior.prorateToAnchor;
  const noCharge = ProrationBehavior.noCharge;

  group('due today', () {
    final preview = MemberMembershipsStartPreview(
      oneTime: invoice(total: 5000),
      dueNow: invoice(total: 3000, proration: true),
      recurring: invoice(total: 12000),
    );

    test('prorating sums the one-time invoice and the amount due now', () {
      expect(dueTodayMinorUnits(preview, prorate), 8000);
    });

    test('no_charge drops the due-now half — nothing bills now', () {
      expect(dueTodayMinorUnits(preview, noCharge), 5000);
    });

    test('no preview is \$0, never a crash', () {
      expect(dueTodayMinorUnits(null, prorate), 0);
    });
  });

  group('two charges today', () {
    test('two non-zero halves are two charges on the statement', () {
      final preview = MemberMembershipsStartPreview(
        oneTime: invoice(total: 5000),
        dueNow: invoice(total: 3000),
      );
      expect(chargedTwiceToday(preview, prorate), isTrue);
      // Under no_charge only the one-time invoice bills, so the warning
      // would be a lie.
      expect(chargedTwiceToday(preview, noCharge), isFalse);
    });

    test('a \$0 one-time invoice is a present invoice, not a second charge', () {
      // An all-trial cart produces a real one-time invoice of $0 lines.
      final preview = MemberMembershipsStartPreview(
        oneTime: invoice(total: 0),
        dueNow: invoice(total: 3000),
      );
      expect(chargedTwiceToday(preview, prorate), isFalse);
    });
  });

  group('proration', () {
    test('read off the LINES own is_proration, not from the figures', () {
      final preview = MemberMembershipsStartPreview(
        dueNow: invoice(total: 3000, proration: true),
      );
      expect(chargedProrated(preview, prorate), isTrue);
      // Suppressed with the due-now half: no part period is being charged.
      expect(chargedProrated(preview, noCharge), isFalse);
    });

    test('differing figures alone never claim a proration', () {
      final preview = MemberMembershipsStartPreview(
        dueNow: invoice(total: 3000),
        recurring: invoice(total: 12000),
      );
      expect(chargedProrated(preview, prorate), isFalse);
    });

    test('prorationUntil falls back to the recurring anchor', () {
      final preview = MemberMembershipsStartPreview(
        dueNow: invoice(total: 3000, nextPaymentDate: 1800000000),
        recurring: invoice(total: 12000, nextPaymentDate: 1900000000),
      );
      expect(prorationUntil(preview, prorate)?.millisecondsSinceEpoch,
          1800000000 * 1000);
      expect(prorationUntil(preview, noCharge)?.millisecondsSinceEpoch,
          1900000000 * 1000);
    });
  });

  group('currency', () {
    test('takes the first half that exists, in preference order', () {
      expect(
        previewCurrency(
          MemberMembershipsStartPreview(
            dueNow: invoice(total: 3000, currency: 'cad'),
            recurring: invoice(total: 12000, currency: 'eur'),
          ),
          prorate,
        ),
        'cad',
      );
    });

    test('a suppressed due-now half does not decide the currency', () {
      expect(
        previewCurrency(
          MemberMembershipsStartPreview(
            dueNow: invoice(total: 3000, currency: 'cad'),
            recurring: invoice(total: 12000, currency: 'eur'),
          ),
          noCharge,
        ),
        'eur',
      );
    });

    test('nothing at all still renders in something', () {
      expect(previewCurrency(null, prorate), 'usd');
    });
  });
}
