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
  // A consolidated invoice the payer (Ashlee) covers for several people:
  // her own membership + a custom charge for two OTHER members. The popup
  // must surface ALL beneficiaries (paid_for is a list) at the top AND on
  // the line items — including a custom/ad-hoc line that is for multiple.
  testWidgets('invoice popup shows multiple paid_for people, top + per line',
      (t) async {
    final payment = PaymentRecord(
      chargeId: 'c1', invoiceId: 'i1', kind: ChargeKind.payment,
      status: ChargeStatus.succeeded, amount: 9000, currency: 'usd',
      chargeTime: DateTime(2026, 6, 22),
      paidByMemberId: 'A', paidByFirstName: 'Ashlee', paidByLastName: 'Sparks',
      paidFor: const [
        PaidForMember(memberId: 'A', firstName: 'Ashlee', lastName: 'Sparks'),
        PaidForMember(
            memberId: 'B', firstName: 'Madison', lastName: 'Blankenship'),
        PaidForMember(memberId: 'C', firstName: 'Jake', lastName: 'Smith'),
      ],
      lineItems: const [
        LineItemRecord(
            lineItemId: 'l1', itemType: LineItemType.membership,
            name: 'Premium Monthly', amount: 5000,
            ownerMemberId: 'A', ownerFirstName: 'Ashlee',
            ownerLastName: 'Sparks'),
        LineItemRecord(
            lineItemId: 'l2', itemType: LineItemType.custom,
            name: 'Family class pack', amount: 4000),
      ],
    );
    await t.pumpWidget(MaterialApp(
        home: Scaffold(body: PaymentInvoiceDialog(payment: payment))));
    await t.pump();

    String? textContaining(String needle) => t
        .widgetList<Text>(find.byType(Text))
        .map((w) => w.data)
        .firstWhere((s) => s != null && s.contains(needle), orElse: () => null);

    // Top attribution: payer + BOTH non-payer beneficiaries.
    expect(textContaining('Paid by Ashlee Sparks'), isNotNull);
    expect(
        textContaining('For Madison Blankenship, Jake Smith'), isNotNull,
        reason: 'top line must list all beneficiaries');
    // Membership line: its single owner.
    expect(textContaining('Premium Monthly · Ashlee Sparks'), isNotNull);
    // Custom/ad-hoc line: ALL beneficiaries it was for (multiple).
    expect(
        textContaining('Family class pack · Madison Blankenship, Jake Smith'),
        isNotNull,
        reason: 'a custom line must show the multiple people it was for');
  });
}
