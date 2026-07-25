import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crm/features/kiosk/bloc/kiosk_signup_state.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_money_panel.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_preview.dart';
import 'package:crm/features/member_details/data/models/payments_invoice_preview.dart';

/// The review's money half names the address payment mail reaches — **and says
/// nothing when there is no address.**
///
/// **It must never promise a receipt.** CombatDen has no mailer at all, and the
/// connected account notifies a member on a FAILED payment only, so a receipt
/// sentence would be a falsehood told on the one screen where money is about to
/// move. The line states what a failure notice would reach instead, which is
/// also the reason the address is worth showing unmasked on a shared iPad.
///
/// An email is required at the details step, so a payer without one is
/// unreachable through the ordinary flow; a payer adopted from the gym's own
/// records can still carry none. With an empty address the sentence would render
/// with a trailing blank, so the line is dropped — the same guard the results
/// panel carries.
void main() {
  Future<void> pumpPanel(
    WidgetTester tester, {
    required String contactEmail,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1180, 820));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: KioskMoneyPanel(
              state: _state(),
              contactEmail: contactEmail,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('a payer WITH an address is told where failure mail lands',
      (tester) async {
    await pumpPanel(tester, contactEmail: 'marcus.bell@gmail.com');

    expect(
      find.text(
        "If a payment ever fails, we'll email you at marcus.bell@gmail.com.",
      ),
      findsOneWidget,
    );
    // Nothing on this screen may claim a receipt is coming: none is sent.
    expect(find.textContaining('receipt'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a payer with NO address gets no receipt line at all',
      (tester) async {
    await pumpPanel(tester, contactEmail: '');

    // Never a trailing blank, and never a promise nothing will keep.
    expect(find.textContaining("we'll email you at"), findsNothing);
    expect(find.textContaining('receipt'), findsNothing);
    // The panel still states the money — the guard drops one line, not the
    // screen.
    expect(find.text('DUE TODAY'), findsOneWidget);
    // The total and its one itemised line both carry the figure.
    expect(find.text('\$149.00'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('whitespace is not an address either', (tester) async {
    await pumpPanel(tester, contactEmail: '   ');

    expect(find.textContaining("we'll email you at"), findsNothing);
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
