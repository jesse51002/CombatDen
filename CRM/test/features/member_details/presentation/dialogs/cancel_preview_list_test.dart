import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:crm/features/member_details/data/models/member_detail_response.dart';
import 'package:crm/features/member_details/data/models/payer_invoice_change.dart';
import 'package:crm/features/member_details/data/models/personal_info.dart';
import 'package:crm/features/member_details/data/models/retention.dart';
import 'package:crm/features/member_details/data/repositories/member_repository.dart';
import 'package:crm/features/member_details/presentation/dialogs/cancel_membership/cancel_preview_list.dart';

class MockMemberRepository extends Mock implements MemberRepository {}

void main() {
  // Minimal member with no memberships — we only need the photo lookup
  // in the preview list, not any membership data.
  const memberId = 'member-1';
  const payerId = 'payer-2';

  final member = MemberDetailResponse(
    memberId: memberId,
    gymId: 'gym-1',
    firstName: 'Sam',
    lastName: 'Lee',
    membershipOverview: '1 membership',
    totalMonthlyRecurringPrice: 10000,
    totalMembershipCount: 1,
    personalInfo: const PersonalInfo(),
    retention: const Retention(
      classStreakWeeks: 0,
      pointsBalance: 0,
      videosWatched: 0,
    ),
  );

  late MockMemberRepository repo;

  setUp(() {
    repo = MockMemberRepository();
    // getUpcomingInvoice may be called when preview is non-null — stub it.
    when(() => repo.getUpcomingInvoice(any()))
        .thenAnswer((_) async => null);
  });

  Widget wrap(Widget child) =>
      MaterialApp(home: Scaffold(body: child));

  // ── null preview → all-cancelled note ────────────────────────────────────

  testWidgets(
    'null preview: shows "no remaining invoice" note, not a spinner',
    (t) async {
      when(
        () => repo.previewCancelMemberships(any(), any()),
      ).thenAnswer(
        (_) async => [
          const PayerInvoiceChange(
            payerMemberId: payerId,
            payerFirstName: 'Jordan',
            payerLastName: 'Smith',
            affected: true,
            preview: null, // all memberships cancelled — no upcoming invoice
          ),
        ],
      );

      await t.pumpWidget(wrap(CancelPreviewList(
        repository: repo,
        member: member,
        itemIds: const ['item-a'],
        fallbackMonthly: 10000,
      )));
      await t.pump(); // resolve future

      // Payer name is shown in the note header.
      expect(find.text('Jordan Smith'), findsOneWidget);
      // The "no remaining invoice" message appears.
      expect(
        find.textContaining('No remaining invoice'),
        findsOneWidget,
      );
      // There must NOT be a loading spinner still showing.
      expect(find.byType(CircularProgressIndicator), findsNothing);
    },
  );

  // ── non-null preview → InvoicePreviewSection renders ─────────────────────

  testWidgets(
    'non-null preview: renders the InvoicePreviewSection container, '
    'not the "no remaining invoice" note',
    (t) async {
      when(
        () => repo.previewCancelMemberships(any(), any()),
      ).thenAnswer(
        (_) async => [
          // preview is non-null — payer still has remaining memberships
          PayerInvoiceChange.fromJson(const {
            'payer_member_id': payerId,
            'payer_first_name': 'Jordan',
            'payer_last_name': 'Smith',
            'affected': true,
            'preview': {
              'due_now': null,
              'recurring': {
                'amount_due': 5000,
                'subtotal': 5000,
                'total': 5000,
                'currency': 'usd',
                'lines': [],
              },
            },
          }),
        ],
      );

      await t.pumpWidget(wrap(CancelPreviewList(
        repository: repo,
        member: member,
        itemIds: const ['item-a'],
        fallbackMonthly: 10000,
      )));
      // Two async layers: outer CancelPreviewList future, then the inner
      // InvoicePreviewSection future. pumpAndSettle drives both to completion.
      await t.pumpAndSettle();

      // The all-cancelled note must NOT appear.
      expect(
        find.textContaining('No remaining invoice'),
        findsNothing,
      );
      // The payer name appears inside InvoiceAttribution (as a separate
      // Text from the "Billed to" caption — InvoiceAttribution uses a Column).
      expect(find.text('Jordan Smith'), findsOneWidget);
    },
  );

  // ── affected=false payers are skipped entirely ────────────────────────────

  testWidgets(
    'affected=false: payer section is not rendered at all',
    (t) async {
      when(
        () => repo.previewCancelMemberships(any(), any()),
      ).thenAnswer(
        (_) async => [
          const PayerInvoiceChange(
            payerMemberId: payerId,
            payerFirstName: 'Jordan',
            payerLastName: 'Smith',
            affected: false, // not affected — no change for this payer
          ),
        ],
      );

      await t.pumpWidget(wrap(CancelPreviewList(
        repository: repo,
        member: member,
        itemIds: const ['item-a'],
        fallbackMonthly: 10000,
      )));
      await t.pump();

      // Neither the payer name nor the no-invoice note renders —
      // the section shows the "no change" fallback text.
      expect(find.text('Jordan Smith'), findsNothing);
      expect(
        find.text('No change to recurring billing.'),
        findsOneWidget,
      );
    },
  );
}
