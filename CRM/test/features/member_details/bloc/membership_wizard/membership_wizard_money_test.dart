import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:crm/core/errors/exceptions.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_cubit.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_derived.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_request.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_step.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_preview.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_request.dart';
import 'package:crm/features/member_details/data/models/plan_type.dart';
import 'package:crm/features/member_details/data/models/proration_behavior.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/custom_card_capture.dart';

import 'membership_wizard_fixtures.dart';

/// The review step's money: one preview, and a proration choice that moves the
/// total without touching the network.
void main() {
  late MockMemberRepository member;
  late MockMembershipsRepository memberships;

  final recurringPlan = plan(planId: 'plan-a', priceId: 'price-a');
  final packPlan = plan(
    planId: 'plan-b',
    priceId: 'price-b',
    type: PlanType.oneTime,
    price: 5000,
  );

  const oneOffCard = CustomCardCapture(
    pmId: 'pm_123',
    brand: 'Visa',
    lastFour: '4242',
  );

  setUpAll(registerWizardFallbacks);

  setUp(() {
    member = MockMemberRepository();
    memberships = MockMembershipsRepository();
    when(() => member.listMembershipPlans(any()))
        .thenAnswer((_) async => [recurringPlan, packPlan]);
    when(() => member.listGymDiscounts(any())).thenAnswer((_) async => []);
    when(() => memberships.listMemberWaiverStatus(any(), any()))
        .thenAnswer((_) async => []);
    when(() => member.previewStartMemberships(any())).thenAnswer(
      (_) async => startPreview(
        oneTime: invoice(total: 5000),
        dueNow: invoice(total: 3000, proration: true),
        recurring: invoice(total: 10000),
      ),
    );
  });

  Future<MembershipWizardCubit> atReview({
    bool mixedCart = true,
  }) async {
    final cubit = buildWizard(
      member: member,
      memberships: memberships,
      launchMember: detail(card: savedCard),
    );
    await cubit.open();
    await cubit.next();
    if (mixedCart) cubit.togglePlan(recurringPlan);
    cubit.togglePlan(packPlan);
    await cubit.next();
    return cubit;
  }

  test('previews at prorate_to_anchor whatever is chosen, and never sends a '
      'card on a preview', () async {
    final cubit = await atReview();
    cubit.setProration(ProrationBehavior.noCharge);
    await cubit.retryPreview();

    final staged = verify(
      () => member.previewStartMemberships(captureAny()),
    ).captured.cast<MemberMembershipsStartRequest>();
    for (final request in staged) {
      expect(
        request.prorationBehavior,
        ProrationBehavior.prorateToAnchor,
        reason: 'the response must carry the FULL split so the toggle can '
            're-derive locally',
      );
      expect(request.payment, isNull);
    }
    await cubit.close();
  });

  test('the proration toggle re-derives LOCALLY — zero repository calls',
      () async {
    final cubit = await atReview();
    verify(() => member.previewStartMemberships(any())).called(1);

    expect(cubit.state.dueTodayMinor, 8000);
    expect(cubit.state.chargedTwice, isTrue);
    expect(cubit.state.prorated, isTrue);

    cubit.setProration(ProrationBehavior.noCharge);

    verifyNever(() => member.previewStartMemberships(any()));
    verifyNever(() => member.startMemberships(any()));
    expect(cubit.state.preview, isNotNull, reason: 'the breakdown never blanks');
    expect(cubit.state.dueTodayMinor, 5000);
    expect(cubit.state.chargedTwice, isFalse);
    expect(cubit.state.prorated, isFalse);
    expect(cubit.state.effectiveDueNowInvoice, isNull);

    cubit.setProration(ProrationBehavior.prorateToAnchor);
    expect(cubit.state.dueTodayMinor, 8000);
    verifyNever(() => member.previewStartMemberships(any()));
    await cubit.close();
  });

  test('a failed preview is retryable rather than a spinner', () async {
    when(() => member.previewStartMemberships(any()))
        .thenThrow(const ServerException('down', statusCode: 500));
    final cubit = await atReview();
    expect(cubit.state.previewLoad.isFailed, isTrue);
    expect(cubit.state.previewLoad.message, isNotEmpty);
    expect(cubit.state.canAdvance, isFalse);

    when(() => member.previewStartMemberships(any()))
        .thenAnswer((_) async => startPreview(recurring: invoice()));
    await cubit.retryPreview();
    expect(cubit.state.previewLoad.isReady, isTrue);
    expect(cubit.state.canAdvance, isTrue);
    await cubit.close();
  });

  group('the one-off card, blocked WITH A REASON', () {
    test('pays a purely one-time cart', () async {
      final cubit = await atReview(mixedCart: false);
      cubit.setCustomCard(oneOffCard);
      expect(cubit.state.oneOffCardBlock, isNull);
      expect(cubit.state.oneOffCardPays, isTrue);
      await cubit.close();
    });

    test('is blocked once the cart turns recurring — and the card SURVIVES',
        () async {
      final cubit = await atReview(mixedCart: false);
      cubit.setCustomCard(oneOffCard);
      cubit.editFromReview('m-payer');
      cubit.togglePlan(recurringPlan);

      expect(cubit.state.oneOffCardBlock, OneOffCardBlock.cartHasRecurring);
      expect(cubit.state.oneOffCardPays, isFalse);
      expect(
        cubit.state.customCard,
        isNotNull,
        reason: 'dropping it would cost staff a re-typed card for a mis-tap',
      );

      cubit.togglePlan(recurringPlan);
      expect(cubit.state.oneOffCardBlock, isNull);
      expect(cubit.state.oneOffCardPays, isTrue);
      await cubit.close();
    });

    test('is blocked while cash is on', () async {
      final cubit = await atReview(mixedCart: false);
      cubit.setCustomCard(oneOffCard);
      cubit.setPaidWithCash(true);
      expect(cubit.state.oneOffCardBlock, OneOffCardBlock.paidWithCash);

      cubit.setPaidWithCash(false);
      expect(cubit.state.oneOffCardBlock, isNull);
      await cubit.close();
    });

    test('is blocked when nothing in the cart bills once', () async {
      final cubit = await atReview(mixedCart: false);
      cubit.editFromReview('m-payer');
      cubit.togglePlan(packPlan);
      cubit.togglePlan(recurringPlan);
      expect(cubit.state.oneOffCardBlock, OneOffCardBlock.cartHasRecurring);

      cubit.togglePlan(recurringPlan);
      expect(cubit.state.hasOneTime, isFalse);
      expect(cubit.state.oneOffCardBlock, OneOffCardBlock.cartHasNoOneTime);
      await cubit.close();
    });
  });

  group('the payment step can be answered', () {
    test('by cash, with no card anywhere', () async {
      final cubit = buildWizard(
        member: member,
        memberships: memberships,
        launchMember: detail(),
      );
      await cubit.open();
      await cubit.next();
      cubit.togglePlan(recurringPlan);
      await cubit.next();
      await cubit.next();
      expect(cubit.state.step, MembershipWizardStep.payment);
      expect(cubit.state.canAdvance, isFalse, reason: 'no card, no cash');

      cubit.setPaidWithCash(true);
      expect(cubit.state.canAdvance, isTrue);
      await cubit.close();
    });

    test('by the payer\'s saved card', () async {
      final cubit = await atReview();
      await cubit.next();
      expect(cubit.state.savedCard, isNotNull);
      expect(cubit.state.canAdvance, isTrue);
      await cubit.close();
    });

    test('by the one-off card alone on a one-time-only cart', () async {
      final cubit = buildWizard(
        member: member,
        memberships: memberships,
        launchMember: detail(),
      );
      await cubit.open();
      await cubit.next();
      cubit.togglePlan(packPlan);
      await cubit.next();
      await cubit.next();
      expect(cubit.state.canAdvance, isFalse);

      cubit.setCustomCard(oneOffCard);
      expect(cubit.state.canAdvance, isTrue);
      await cubit.close();
    });
  });

  test('entering the payment step mints one key per arrival', () async {
    final cubit = await atReview();
    await cubit.next();
    final first = cubit.state.idempotencyKey;
    expect(first, isNotNull);

    await cubit.back();
    await cubit.next();
    expect(cubit.state.idempotencyKey, isNot(first));
    await cubit.close();
  });

  group('a preview that answers out of order', () {
    /// The trash on the review is a tap, not an awaited call, so two of them
    /// inside one round-trip leave two previews in flight — and nothing makes
    /// the network answer in the order it was asked.
    test('never lands a superseded cart\'s total on the live cart', () async {
      final third = plan(planId: 'plan-c', priceId: 'price-c', price: 2000);
      when(() => member.listMembershipPlans(any()))
          .thenAnswer((_) async => [recurringPlan, packPlan, third]);
      final pending = <Completer<MemberMembershipsStartPreview>>[];
      when(() => member.previewStartMemberships(any())).thenAnswer((_) {
        final answer = Completer<MemberMembershipsStartPreview>();
        pending.add(answer);
        return answer.future;
      });

      final cubit = buildWizard(
        member: member,
        memberships: memberships,
        launchMember: detail(card: savedCard),
      );
      await cubit.open();
      await cubit.next();
      cubit.togglePlan(recurringPlan);
      cubit.togglePlan(packPlan);
      cubit.togglePlan(third);
      final arriving = cubit.next();
      pending[0].complete(startPreview(dueNow: invoice(total: 17000)));
      await arriving;
      expect(cubit.state.dueTodayMinor, 17000);

      // Two trash taps, back to back. Neither is awaited — that is what the
      // widget does.
      cubit.removeMembership('m-payer', 'plan-c');
      cubit.removeMembership('m-payer', 'plan-b');
      expect(pending.length, 3, reason: 'both edits re-staged a preview');

      // The LIVE cart's total arrives first...
      pending[2].complete(startPreview(dueNow: invoice(total: 10000)));
      await pumpEventQueue();
      expect(cubit.state.dueTodayMinor, 10000);

      // ...and the two-membership cart's answer arrives after it. It priced a
      // cart that no longer exists, so it is dropped rather than rendered
      // `ready` over the live one with PAY enabled.
      pending[1].complete(startPreview(dueNow: invoice(total: 15000)));
      await pumpEventQueue();
      expect(
        cubit.state.dueTodayMinor,
        10000,
        reason: 'quoting one number and charging another is the failure this '
            'whole step exists to prevent',
      );
      await cubit.close();
    });

    /// The same guard on the unhappy paths: a superseded answer must not blank
    /// a live quote, and a superseded 422 must not demand a signature for a
    /// cart that is gone.
    test('never lets a superseded failure blank the live quote', () async {
      final pending = <Completer<MemberMembershipsStartPreview>>[];
      when(() => member.previewStartMemberships(any())).thenAnswer((_) {
        final answer = Completer<MemberMembershipsStartPreview>();
        pending.add(answer);
        return answer.future;
      });

      final cubit = buildWizard(
        member: member,
        memberships: memberships,
        launchMember: detail(card: savedCard),
      );
      await cubit.open();
      await cubit.next();
      cubit.togglePlan(recurringPlan);
      final arriving = cubit.next();

      // A second Retry tap while the first read is still out.
      cubit.retryPreview();
      pending[1].complete(startPreview(dueNow: invoice(total: 13000)));
      await pumpEventQueue();
      expect(cubit.state.previewLoad.isReady, isTrue);

      pending[0].completeError(Exception('the first attempt, answering late'));
      await arriving;
      await pumpEventQueue();
      expect(cubit.state.previewLoad.isReady, isTrue);
      expect(cubit.state.dueTodayMinor, 13000);
      await cubit.close();
    });
  });
}
