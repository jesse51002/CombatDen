import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crm/features/kiosk/bloc/kiosk_signup_state.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_money_panel.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_preview.dart';
import 'package:crm/features/member_details/data/models/payments_invoice_preview.dart';

/// The review's money half says where the receipt lands — **and says nothing
/// when there is nowhere for it to land.**
///
/// An email is required at the details step, so a payer without one is
/// unreachable through the ordinary flow; a payer adopted from the gym's own
/// records can still carry none. With an empty address the sentence renders as
/// the broken "Your receipt goes to ." AND promises a receipt nothing will ever
/// send, on the one screen where money is about to move. The line is dropped
/// instead — the same guard the results receipt carries.
void main() {
  Future<void> pumpPanel(
    WidgetTester tester, {
    required String receiptEmail,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1180, 820));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: KioskMoneyPanel(
              state: _state(),
              receiptEmail: receiptEmail,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('a payer WITH an address is told where the receipt goes',
      (tester) async {
    await pumpPanel(tester, receiptEmail: 'marcus.bell@gmail.com');

    expect(
      find.text('Your receipt goes to marcus.bell@gmail.com.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a payer with NO address gets no receipt line at all',
      (tester) async {
    await pumpPanel(tester, receiptEmail: '');

    // Never the broken sentence, and never a promise nothing will keep.
    expect(find.textContaining('Your receipt goes to'), findsNothing);
    // The panel still states the money — the guard drops one line, not the
    // screen.
    expect(find.text('DUE TODAY'), findsOneWidget);
    // The total and its one itemised line both carry the figure.
    expect(find.text('\$149.00'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('whitespace is not an address either', (tester) async {
    await pumpPanel(tester, receiptEmail: '   ');

    expect(find.textContaining('Your receipt goes to'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

/// A review state with a real preview behind it, so the panel renders the whole
/// money block rather than an empty shell.
KioskSignupState _state() => KioskSignupState(
      step: KioskSignupStep.review,
      persons: const [
        KioskSignupPerson(
          memberId: 'mem-1',
          firstName: 'Marcus',
          lastName: 'Bell',
          isPayer: true,
        ),
      ],
      cardBrand: 'visa',
      cardLast4: '4242',
      preview: MemberMembershipsStartPreview(
        dueNow: PreviewInvoice(
          amountDue: 14900,
          subtotal: 14900,
          total: 14900,
          currency: 'usd',
          lines: [
            PreviewInvoiceLine(
              amount: 14900,
              discountedAmount: 14900,
              description: 'Unlimited',
            ),
          ],
        ),
      ),
    );
