import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crm/features/member_details/data/models/charge_kind.dart';
import 'package:crm/features/member_details/data/models/charge_status.dart';
import 'package:crm/features/member_details/data/models/line_item_record.dart';
import 'package:crm/features/member_details/data/models/line_item_type.dart';
import 'package:crm/features/member_details/data/models/paid_for_member.dart';
import 'package:crm/features/member_details/data/models/payment_record.dart';
import 'package:crm/features/member_details/presentation/dialogs/payment_invoice_dialog.dart';

void main() {
  // paid_for is a LIST; the popup must surface multiple beneficiaries at the
  // top AND on line items — including a CONSOLIDATED membership line shared by
  // several co-owners (one Stripe item, quantity > 1) and a custom/ad-hoc line.
  testWidgets('popup shows multiple people: top + consolidated + custom lines',
      (t) async {
    final payment = PaymentRecord(
      chargeId: 'c1', invoiceId: 'i1', kind: ChargeKind.payment,
      status: ChargeStatus.succeeded, amount: 12000, currency: 'usd',
      chargeTime: DateTime(2026, 6, 22),
      paidByMemberId: 'D', paidByFirstName: 'Daniel', paidByLastName: 'Jordan',
      paidFor: const [
        PaidForMember(memberId: 'CA', firstName: 'Carrie', lastName: 'Hebert'),
        PaidForMember(
            memberId: 'CH', firstName: 'Christopher', lastName: 'Davis'),
      ],
      lineItems: const [
        // A consolidated membership line (qty 2) shared by TWO co-owners.
        LineItemRecord(
            lineItemId: 'l1', itemType: LineItemType.membership,
            name: 'Remaining time on 2 × Monthly', amount: 2770, quantity: 2,
            ownerLabel: 'Carrie Hebert, Christopher Davis'),
        // A custom/ad-hoc line: no owner -> falls back to paid_for.
        LineItemRecord(
            lineItemId: 'l2', itemType: LineItemType.custom,
            name: 'Family class pack', amount: 4000),
      ],
    );
    await t.pumpWidget(MaterialApp(
        home: Scaffold(body: PaymentInvoiceDialog(payment: payment))));
    await t.pump();

    String? has(String needle) => t
        .widgetList<Text>(find.byType(Text))
        .map((w) => w.data)
        .firstWhere((s) => s != null && s.contains(needle), orElse: () => null);

    // Top: payer + BOTH beneficiaries.
    expect(has('Paid by Daniel Jordan'), isNotNull);
    expect(has('For Carrie Hebert, Christopher Davis'), isNotNull);
    // THE BUG: a single consolidated line must show BOTH co-owners.
    expect(has('2 × Monthly ×2 · Carrie Hebert, Christopher Davis'), isNotNull,
        reason: 'a consolidated line is for multiple people');
    // Custom line falls back to the invoice beneficiaries.
    expect(has('Family class pack · Carrie Hebert, Christopher Davis'),
        isNotNull);
  });
}
