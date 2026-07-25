import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crm/features/kiosk/bloc/kiosk_signup_state.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_review_group_panel.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_review_side_panel.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_response.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_result_item.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_status.dart';
import 'package:crm/features/member_details/data/models/membership_plan_price_response.dart';
import 'package:crm/features/member_details/data/models/membership_plan_response.dart';
import 'package:crm/features/member_details/data/models/plan_type.dart';

/// The review's left half, on the two things it must not get wrong.
///
/// **1 · No screen in this lane prints a stored address in full for
/// IDENTIFICATION.** The solo review's "YOU" row is an identification line —
/// it exists so the member can tell "that's my account" — and a lobby iPad has
/// a queue reading over the member's shoulder, so it masks like the roster row,
/// the payer picker and the match card do. The deliberate exceptions are the two
/// RECEIPT lines (the money panel's "Your receipt goes to …" and the results
/// receipt's), which exist so the payer can verify where a receipt lands and
/// therefore need the real address.
///
/// **2 · After a PARTIAL failure the group panel MARKS the people whose
/// membership already started; it never drops their row.** The panel lists
/// everybody on purpose (a non-training payer included), so hiding a row would
/// read as "we forgot them" — while leaving it unmarked would imply the card
/// about to be entered is charged for them again.
void main() {
  Future<void> pumpPanel(WidgetTester tester, Widget panel) async {
    await tester.binding.setSurfaceSize(const Size(1180, 820));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: panel)),
      ),
    );
    await tester.pump();
  }

  group('the solo review masks the payer\'s own address', () {
    testWidgets('the YOU row prints the masked form, never the full one',
        (tester) async {
      await pumpPanel(
        tester,
        KioskReviewSidePanel(state: _soloState()),
      );

      expect(find.text('m•••••@gmail.com'), findsOneWidget);
      expect(find.text('marcus.bell@gmail.com'), findsNothing);
      // The row still identifies them — masking a line is not dropping it.
      expect(find.text('Marcus Bell'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a payer with NO address gets no second line at all',
        (tester) async {
      await pumpPanel(
        tester,
        KioskReviewSidePanel(state: _soloState(email: '')),
      );

      // Nothing to mask means nothing to print, never an empty line.
      expect(find.textContaining('•'), findsNothing);
      expect(find.text('Marcus Bell'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('the group review marks an already-started person', () {
    testWidgets('their row stays, wearing STARTED, and the ones still being '
        'charged do not', (tester) async {
      await pumpPanel(
        tester,
        KioskReviewGroupPanel(state: _groupStateAfterPartial()),
      );

      // Everybody is still listed — the panel marks, it never filters.
      expect(find.text('Marcus Bell'), findsOneWidget);
      expect(find.text('Ella Bell'), findsOneWidget);
      expect(find.text('Sam Bell'), findsOneWidget);
      // Ella's membership landed on the earlier attempt; the other two are what
      // the next card is charged for.
      expect(find.text('STARTED'), findsOneWidget);
      // The role labels survive alongside it: the payer is still marked PAYING,
      // which is the fact that explains the whole screen.
      expect(find.text('PAYING'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('nothing is marked before a start has landed', (tester) async {
      await pumpPanel(
        tester,
        KioskReviewGroupPanel(state: _groupState()),
      );

      // A first attempt carries the whole cart, so no row has "already paid"
      // to say — the mark is derived from a landed response, never from a
      // person who simply is not being charged.
      expect(find.text('STARTED'), findsNothing);
      expect(find.text('PAYING'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a NON-training payer is never marked started', (tester) async {
      // They are not in the cart at all, so `isBeingCharged` is false for them
      // for a completely different reason. Marking them STARTED would claim a
      // membership they never bought.
      await pumpPanel(
        tester,
        KioskReviewGroupPanel(state: _groupStateAfterPartial(payerTrains: false)),
      );

      expect(find.text('STARTED'), findsOneWidget);
      expect(find.text('PAYING'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

MembershipPlanResponse _plan() => MembershipPlanResponse(
      planId: 'plan-1',
      gymId: 'gym-1',
      planName: 'Unlimited',
      // Empty so the row draws the shipped tick square rather than reaching for
      // a network image in a widget test.
      imageUrl: '',
      planType: PlanType.recurring,
      durationAmount: 1,
      isPublic: true,
      createdAt: DateTime.utc(2026),
      waiverIds: const ['waiver-1'],
      activePrice: MembershipPlanPriceResponse(
        priceId: 'price-1',
        planId: 'plan-1',
        gymId: 'gym-1',
        stripePriceId: 'price_stripe',
        price: 14900,
        isActive: true,
        createdAt: DateTime.utc(2026),
      ),
    );

KioskSignupState _soloState({String email = 'marcus.bell@gmail.com'}) =>
    KioskSignupState(
      step: KioskSignupStep.review,
      plans: [_plan()],
      persons: [
        KioskSignupPerson(
          memberId: 'mem-1',
          firstName: 'Marcus',
          lastName: 'Bell',
          email: email,
          isPayer: true,
          selectedPlanId: 'plan-1',
        ),
      ],
    );

/// A family of three, everybody buying, nothing landed yet.
KioskSignupState _groupState({
  MemberMembershipsStartResponse? landed,
  bool payerTrains = true,
}) =>
    KioskSignupState(
      step: KioskSignupStep.review,
      plans: [_plan()],
      startResult: landed,
      persons: [
        KioskSignupPerson(
          memberId: 'mem-1',
          firstName: 'Marcus',
          lastName: 'Bell',
          email: 'marcus.bell@gmail.com',
          isPayer: true,
          training: payerTrains,
          selectedPlanId: payerTrains ? 'plan-1' : null,
        ),
        const KioskSignupPerson(
          memberId: 'mem-2',
          firstName: 'Ella',
          lastName: 'Bell',
          email: 'ella.bell@gmail.com',
          selectedPlanId: 'plan-1',
        ),
        const KioskSignupPerson(
          memberId: 'mem-3',
          firstName: 'Sam',
          lastName: 'Bell',
          email: 'sam.bell@gmail.com',
          selectedPlanId: 'plan-1',
        ),
      ],
    );

/// The same family after a partial: Ella's membership was CREATED, the other two
/// were refused, and the member came back through "Try another card".
KioskSignupState _groupStateAfterPartial({bool payerTrains = true}) =>
    _groupState(
      payerTrains: payerTrains,
      landed: MemberMembershipsStartResponse(
        chargeCount: 1,
        multipleCharges: false,
        results: [
          for (final id in const ['mem-1', 'mem-2', 'mem-3'])
            if (payerTrains || id != 'mem-1')
              MemberMembershipsStartResultItem(
                memberId: id,
                planId: 'plan-1',
                planType: PlanType.recurring,
                status: id == 'mem-2'
                    ? MemberMembershipsStartStatus.created
                    : MemberMembershipsStartStatus.failed,
                itemId: id == 'mem-2' ? 'item-2' : null,
                error: id == 'mem-2' ? null : 'card_declined',
              ),
        ],
      ),
    );
