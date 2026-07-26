import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:crm/core/errors/exceptions.dart';
import 'package:crm/features/kiosk/bloc/kiosk_session_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_state.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_preview.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_request.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_response.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_result_item.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_status.dart';
import 'package:crm/features/member_details/data/models/members_management_create_request.dart';
import 'package:crm/features/member_details/data/models/members_management_response.dart';
import 'package:crm/features/member_details/data/models/members_management_update_request.dart';
import 'package:crm/features/member_details/data/models/membership_plan_price_response.dart';
import 'package:crm/features/member_details/data/models/membership_plan_response.dart';
import 'package:crm/features/member_details/data/models/payments_invoice_preview.dart';
import 'package:crm/features/member_details/data/models/plan_type.dart';
import 'package:crm/features/member_details/data/models/proration_behavior.dart';
import 'package:crm/features/member_details/data/repositories/member_repository.dart';
import 'package:crm/features/members_list/data/repositories/members_list_repository.dart';
import 'package:crm/features/memberships/data/models/waiver_response.dart';
import 'package:crm/features/memberships/data/models/waiver_signature_response.dart';
import 'package:crm/features/memberships/data/models/waiver_type.dart';
import 'package:crm/features/memberships/data/models/waiver_version_response.dart';
import 'package:crm/features/memberships/data/repositories/memberships_repository.dart';
import 'package:crm/features/emails/data/models/invite_outcome.dart';
import 'package:crm/features/member_details/data/models/member_create_result.dart';

class _MockMemberRepository extends Mock implements MemberRepository {}

class _MockMembershipsRepository extends Mock
    implements MembershipsRepository {}

class _MockMembersListRepository extends Mock
    implements MembersListRepository {}

class _MockKioskSessionCubit extends Mock implements KioskSessionCubit {}

class _MockManagementResponse extends Mock
    implements MembersManagementResponse {}

class _MockSignatureResponse extends Mock implements WaiverSignatureResponse {}

/// The kiosk signup's MONEY path — plan pick, waivers, card, review, and the
/// pay / declined / welcome terminals. Getting one of these wrong charges a
/// real card twice, takes money and shows a blank screen, or leaks the
/// session's flow count so the iPad never signs itself out at its lockout.
void main() {
  const gymId = 'gym-1';
  const planId = 'plan-1';
  const priceId = 'price-1';
  const waiverId = 'waiver-1';
  final t0 = DateTime.utc(2026, 1, 1, 18);

  late _MockMemberRepository member;
  late _MockMembershipsRepository memberships;
  late _MockMembersListRepository membersList;
  late _MockKioskSessionCubit session;
  late int uuidSeq;

  setUpAll(() {
    registerFallbackValue(
      const MembersManagementCreateRequest(
        sendInvite: true,
        gymId: gymId,
        firstName: 'a',
        lastName: 'b',
      ),
    );
    registerFallbackValue(const MembersManagementUpdateRequest());
    registerFallbackValue(
      const MemberMembershipsStartRequest(
        payerMemberId: 'm',
        gymId: gymId,
        idempotencyKey: 'k',
        memberships: [],
      ),
    );
  });

  setUp(() {
    member = _MockMemberRepository();
    memberships = _MockMembershipsRepository();
    membersList = _MockMembersListRepository();
    session = _MockKioskSessionCubit();
    uuidSeq = 0;

    when(() => memberships.listPlans(any()))
        .thenAnswer((_) async => [_recurringPlan()]);
    when(() => memberships.getWaiver(any(), any()))
        .thenAnswer((_) async => _waiver());
    when(
      () => memberships.recordWaiverSignature(
        waiverId: any(named: 'waiverId'),
        gymId: any(named: 'gymId'),
        memberId: any(named: 'memberId'),
        waiverVersionId: any(named: 'waiverVersionId'),
        signerName: any(named: 'signerName'),
      ),
    ).thenAnswer((_) async => _MockSignatureResponse());
    when(() => member.createMember(any())).thenAnswer((_) async => MemberCreateResult(
          memberId: 'mem-new',
          invite: InviteOutcome.queued,
        ));
    when(() => member.updateMember(any(), any()))
        .thenAnswer((_) async => _MockManagementResponse());
    when(() => member.previewStartMemberships(any()))
        .thenAnswer((_) async => _preview());
    when(
      () => member.startMemberships(
        any(),
        receiveTimeout: any(named: 'receiveTimeout'),
      ),
    ).thenAnswer((_) async => _startResponse());
  });

  KioskSignupCubit build() => KioskSignupCubit(
        memberRepository: member,
        membershipsRepository: memberships,
        membersListRepository: membersList,
        session: session,
        gymId: gymId,
        now: () => t0,
        // Every key is distinct, so "a NEW key" is a real assertion rather
        // than an artefact of a constant stub.
        uuid: () => 'key-${++uuidSeq}',
      );

  /// Walk a solo signup from the first field to the review, ready to pay.
  Future<KioskSignupCubit> atReview() async {
    final cubit = build();
    cubit.submitDetails(
      firstName: 'Marcus',
      lastName: 'Bell',
      email: 'marcus.bell@gmail.com',
    );
    await cubit.submitExtraDetails();
    cubit.continueToPlans();
    cubit.selectPlan(planId);
    cubit.continueFromPlans();
    await _settle();
    await cubit.signWaiver(signerName: 'Marcus Bell');
    expect(cubit.state.step, KioskSignupStep.card);
    cubit.submitCard(
      paymentMethodId: 'pm_1',
      brand: 'visa',
      last4: '4242',
    );
    await _settle();
    expect(cubit.state.step, KioskSignupStep.review);
    return cubit;
  }

  group('the request builder — the single place to audit', () {
    test('sends nothing price-reducing, no cash, and one item at quantity 1',
        () async {
      final cubit = await atReview();
      final request = verify(() => member.previewStartMemberships(captureAny()))
          .captured
          .single as MemberMembershipsStartRequest;

      expect(request.payerMemberId, 'mem-new');
      expect(request.gymId, gymId);
      expect(request.paidWithCash, isFalse);
      expect(request.prorationBehavior, ProrationBehavior.prorateToAnchor);
      // A preview never carries a card.
      expect(request.payment, isNull);

      final item = request.memberships.single;
      expect(item.memberId, 'mem-new');
      expect(item.priceId, priceId);
      expect(item.quantity, 1);
      // The two fields a kiosk may never populate.
      expect(item.discountIds, isEmpty);
      expect(item.customDiscounts, isEmpty);
      await cubit.close();
    });

    test('the PAY call sends the fresh card with set_default on a RECURRING '
        'cart', () async {
      final cubit = await atReview();
      await cubit.pay();

      final request = verify(
        () => member.startMemberships(
          captureAny(),
          receiveTimeout: kKioskSignupStartTimeout,
        ),
      ).captured.single as MemberMembershipsStartRequest;
      final payment = request.payment!;
      // The CRM wizard sends no card for a recurring cart (it reuses the saved
      // default); the kiosk has none to reuse and the backend rejects that.
      expect(payment.paymentMethodId, 'pm_1');
      expect(payment.setDefault, isTrue);
      expect(request.paidWithCash, isFalse);
      expect(cubit.state.step, KioskSignupStep.results);
      await cubit.close();
    });

    test('set_default is true on a ONE-TIME-ONLY cart too', () async {
      // No branch on the cart: the kiosk always saves the entered card as the
      // payer's default, replacing theirs. The card step says so.
      when(() => memberships.listPlans(any()))
          .thenAnswer((_) async => [_oneTimePlan()]);
      final cubit = await atReview();
      expect(cubit.state.cartHasRecurring, isFalse);
      await cubit.pay();

      final request = verify(
        () => member.startMemberships(
          captureAny(),
          receiveTimeout: kKioskSignupStartTimeout,
        ),
      ).captured.single as MemberMembershipsStartRequest;
      expect(request.payment!.setDefault, isTrue);
      await cubit.close();
    });
  });

  group('double-tap Pay is exactly ONE charge', () {
    test('two synchronous taps make one repository call', () async {
      final cubit = await atReview();
      // Two taps in the same frame. `pay()` guards synchronously and emits
      // `paying` BEFORE its first await, so the second tap sees the new step.
      final first = cubit.pay();
      final second = cubit.pay();
      await Future.wait([first, second]);

      verify(
        () => member.startMemberships(
          any(),
          receiveTimeout: any(named: 'receiveTimeout'),
        ),
      ).called(1);
      await cubit.close();
    });

    test('a key that has already been sent is NEVER posted again', () async {
      when(
        () => member.startMemberships(
          any(),
          receiveTimeout: any(named: 'receiveTimeout'),
        ),
      ).thenThrow(const NetworkException('connection dropped'));
      final cubit = await atReview();
      await cubit.pay();
      expect(cubit.state.step, KioskSignupStep.stop);

      // The outcome is unknown, so a second pay must not re-post it — an
      // auto-retry is the one action that could double-charge.
      await cubit.pay();
      verify(
        () => member.startMemberships(
          any(),
          receiveTimeout: any(named: 'receiveTimeout'),
        ),
      ).called(1);
      expect(
        cubit.state.stopReason,
        KioskSignupStopReason.paymentUnconfirmed,
      );
      await cubit.close();
    });
  });

  group('start-call response routing', () {
    test('201 with every item created lands on the RESULTS receipt and '
        'releases the flow exactly once', () async {
      final cubit = await atReview();
      verifyNever(() => session.endFlow());
      await cubit.pay();

      expect(cubit.state.step, KioskSignupStep.results);
      expect(cubit.state.allCreated, isTrue);
      verify(() => session.endFlow()).called(1);

      // `_enterWelcome`'s own release is a latch no-op, not a second decrement.
      cubit.nextFromResults();
      expect(cubit.state.step, KioskSignupStep.welcome);
      // Nothing outstanding, so the welcome says nothing about the desk.
      expect(cubit.state.welcomeAfterPartial, isFalse);
      verifyNever(() => session.endFlow());
      await cubit.close();
      // Still exactly once after teardown — the latch holds.
      verifyNever(() => session.endFlow());
    });

    test('the receipt carries its own 60-second return countdown, and the flow '
        'is released EXACTLY once across it', () {
      fakeAsync((async) {
        final cubit = build();
        cubit.submitDetails(
          firstName: 'Marcus',
          lastName: 'Bell',
          email: 'marcus.bell@gmail.com',
        );
        cubit.submitExtraDetails();
        async.elapse(Duration.zero);
        cubit.continueToPlans();
        cubit.selectPlan(planId);
        cubit.continueFromPlans();
        async.elapse(Duration.zero);
        cubit.signWaiver(signerName: 'Marcus Bell');
        async.elapse(Duration.zero);
        cubit.submitCard(paymentMethodId: 'pm_1', brand: 'visa', last4: '4242');
        async.elapse(Duration.zero);
        cubit.pay();
        async.elapse(Duration.zero);

        expect(cubit.state.step, KioskSignupStep.results);
        expect(cubit.state.popupCountdown, kKioskSignupPopupHold.inSeconds);
        // Every item created, so the count is released on ENTRY.
        verify(() => session.endFlow()).called(1);

        async.elapse(const Duration(seconds: 30));
        expect(cubit.state.popupCountdown, 30);
        expect(cubit.state.abandoned, isFalse);

        async.elapse(kKioskSignupPopupHold);
        // Expiry runs the ordinary abandon; its release is a latch no-op, so
        // the pair stays exactly-once. An unbalanced count never signs out.
        expect(cubit.state.abandoned, isTrue);
        verifyNever(() => session.endFlow());
        cubit.close();
        async.flushTimers();
      });
    });

    test('ALL items refused stays on the decline popup, whose "nothing was '
        'charged" is true there', () async {
      when(
        () => member.startMemberships(
          any(),
          receiveTimeout: any(named: 'receiveTimeout'),
        ),
      ).thenAnswer((_) async => _startResponse(failed: true));
      final cubit = await atReview();
      await cubit.pay();

      expect(cubit.state.step, KioskSignupStep.declined);
      verifyNever(() => session.endFlow());
      await cubit.close();
    });

    test('409 is an idempotent REPLAY: treated as success, never re-charged',
        () async {
      when(
        () => member.startMemberships(
          any(),
          receiveTimeout: any(named: 'receiveTimeout'),
        ),
      ).thenThrow(
        ServerException('Server error 409', statusCode: 409),
      );
      final cubit = await atReview();
      await cubit.pay();

      // The ORIGINAL start stands — rows, signatures and charge included.
      expect(cubit.state.step, KioskSignupStep.welcome);
      verify(
        () => member.startMemberships(
          any(),
          receiveTimeout: any(named: 'receiveTimeout'),
        ),
      ).called(1);
      verify(() => session.endFlow()).called(1);
      await cubit.close();
    });

    test('422 waiver gate routes back to the waiver step, seeded with the '
        'unsigned list', () async {
      when(
        () => member.startMemberships(
          any(),
          receiveTimeout: any(named: 'receiveTimeout'),
        ),
      ).thenThrow(
        const WaiverGateException(
          message: 'unsigned',
          unsigned: [
            WaiverGateItem(
              memberId: 'mem-new',
              waiverId: waiverId,
              name: 'Liability Waiver',
            ),
          ],
        ),
      );
      final cubit = await atReview();
      await cubit.pay();
      await _settle();

      expect(cubit.state.step, KioskSignupStep.waivers);
      expect(cubit.state.waiverQueue, [waiverId]);
      // A waiver the server calls unsigned is dropped from our own signed set,
      // or the step would skip it and loop.
      expect(cubit.state.signedWaiverIds, isEmpty);
      // The flow is still live — a gate is not a terminal.
      verifyNever(() => session.endFlow());
      await cubit.close();
    });

    test('a 500 stops with "nothing was charged" and does not auto-retry',
        () async {
      when(
        () => member.startMemberships(
          any(),
          receiveTimeout: any(named: 'receiveTimeout'),
        ),
      ).thenThrow(ServerException('Server error 500', statusCode: 500));
      final cubit = await atReview();
      await cubit.pay();

      expect(cubit.state.step, KioskSignupStep.stop);
      expect(cubit.state.stopReason, KioskSignupStopReason.paymentFailed);
      expect(cubit.state.stopReason!.isRetryable, isFalse);
      verify(
        () => member.startMemberships(
          any(),
          receiveTimeout: any(named: 'receiveTimeout'),
        ),
      ).called(1);
      verify(() => session.endFlow()).called(1);
      await cubit.close();
    });
  });

  group('declined — retries the CHARGE and nothing else', () {
    test('a 207 declines, holds the flow count, and keeps the card for retry',
        () async {
      when(
        () => member.startMemberships(
          any(),
          receiveTimeout: any(named: 'receiveTimeout'),
        ),
      ).thenAnswer((_) async => _startResponse(failed: true));
      final cubit = await atReview();
      await cubit.pay();

      expect(cubit.state.step, KioskSignupStep.declined);
      expect(cubit.state.failedItems, hasLength(1));
      // The card the member entered is kept — it is what "Retry" re-uses.
      expect(cubit.state.paymentMethodId, 'pm_1');
      // The member is still standing there: a decline is NOT an exit.
      verifyNever(() => session.endFlow());
      await cubit.close();
    });

    test('"Try another card" uses a NEW key and a NEW card, re-creating or '
        're-signing nothing', () async {
      when(
        () => member.startMemberships(
          any(),
          receiveTimeout: any(named: 'receiveTimeout'),
        ),
      ).thenAnswer((_) async => _startResponse(failed: true));
      final cubit = await atReview();
      await cubit.pay();
      final firstKey = cubit.state.idempotencyKey;

      clearInteractions(member);
      clearInteractions(memberships);
      cubit.retryCard();
      expect(cubit.state.step, KioskSignupStep.card);
      // The element is cleared: this path must carry a genuinely new card.
      expect(cubit.state.paymentMethodId, isNull);

      cubit.submitCard(
        paymentMethodId: 'pm_2',
        brand: 'visa',
        last4: '1881',
      );
      await _settle();
      await cubit.pay();

      final request = verify(
        () => member.startMemberships(
          captureAny(),
          receiveTimeout: any(named: 'receiveTimeout'),
        ),
      ).captured.single as MemberMembershipsStartRequest;
      expect(request.idempotencyKey, isNot(firstKey));
      expect(request.payment!.paymentMethodId, 'pm_2');
      // Everything else is committed — a retry re-executes the CHARGE only.
      verifyNever(() => member.createMember(any()));
      verifyNever(
        () => memberships.recordWaiverSignature(
          waiverId: any(named: 'waiverId'),
          gymId: any(named: 'gymId'),
          memberId: any(named: 'memberId'),
          waiverVersionId: any(named: 'waiverVersionId'),
          signerName: any(named: 'signerName'),
        ),
      );
      expect(cubit.state.signedWaiverIds, [waiverId]);
      await cubit.close();
    });

    test('each "Try another card" bumps cardAttempt, so the card field is '
        're-keyed and mounts a fresh, empty Stripe iframe', () async {
      when(
        () => member.startMemberships(
          any(),
          receiveTimeout: any(named: 'receiveTimeout'),
        ),
      ).thenAnswer((_) async => _startResponse(failed: true));
      final cubit = await atReview();
      expect(cubit.state.cardAttempt, 0);

      await cubit.pay();
      expect(cubit.state.step, KioskSignupStep.declined);
      cubit.retryCard();
      // The widget keys off this nonce (`ValueKey('kiosk-card-$cardAttempt')`),
      // so the returning card step mounts a brand-new iframe.
      expect(cubit.state.cardAttempt, 1);

      cubit.submitCard(paymentMethodId: 'pm_2', brand: 'visa', last4: '1881');
      await _settle();
      await cubit.pay();
      cubit.retryCard();
      expect(cubit.state.cardAttempt, 2);
      await cubit.close();
    });

    test('a decline is NEVER terminal or gated — the member retries the same '
        'card, uncapped and with no wait', () async {
      when(
        () => member.startMemberships(
          any(),
          receiveTimeout: any(named: 'receiveTimeout'),
        ),
      ).thenAnswer((_) async => _startResponse(failed: true));
      final cubit = await atReview();

      await cubit.pay();
      // From here on, nothing already committed may be touched again.
      clearInteractions(member);
      clearInteractions(memberships);
      final keys = <String>[cubit.state.idempotencyKey!];
      // Every retry fires immediately — there is no cooldown to gate it.
      for (var i = 2; i <= 8; i++) {
        expect(cubit.state.step, KioskSignupStep.declined);
        cubit.retrySameCard();
        await _settle();
        keys.add(cubit.state.idempotencyKey!);
      }

      expect(cubit.state.step, KioskSignupStep.declined);
      expect(cubit.state.stopReason, isNull);
      // Every retry is a genuinely new attempt.
      expect(keys.toSet().length, keys.length);
      // The SAME card was re-sent every time — never cleared, never re-keyed.
      expect(cubit.state.cardAttempt, 0);
      expect(cubit.state.paymentMethodId, 'pm_1');
      // Nothing already committed is ever re-executed.
      verifyNever(() => member.createMember(any()));
      verifyNever(
        () => memberships.recordWaiverSignature(
          waiverId: any(named: 'waiverId'),
          gymId: any(named: 'gymId'),
          memberId: any(named: 'memberId'),
          waiverVersionId: any(named: 'waiverVersionId'),
          signerName: any(named: 'signerName'),
        ),
      );
      // The flow count is NOT released on `declined`.
      verifyNever(() => session.endFlow());
      await cubit.close();
    });

    test('"Retry" re-attempts the SAME card with a NEW key, re-sending only '
        'the failed items and re-running nothing else', () async {
      when(
        () => member.startMemberships(
          any(),
          receiveTimeout: any(named: 'receiveTimeout'),
        ),
      ).thenAnswer((_) async => _startResponse(failed: true));
      final cubit = await atReview();
      await cubit.pay();
      expect(cubit.state.step, KioskSignupStep.declined);
      final firstKey = cubit.state.idempotencyKey;

      clearInteractions(member);
      clearInteractions(memberships);
      // The member moved funds; the same card now approves.
      when(
        () => member.startMemberships(
          any(),
          receiveTimeout: any(named: 'receiveTimeout'),
        ),
      ).thenAnswer((_) async => _startResponse());

      cubit.retrySameCard();
      await _settle();

      final request = verify(
        () => member.startMemberships(
          captureAny(),
          receiveTimeout: any(named: 'receiveTimeout'),
        ),
      ).captured.single as MemberMembershipsStartRequest;
      // The SAME card with a genuinely NEW key: reusing the sent key would
      // replay the decline through the latch.
      expect(request.payment!.paymentMethodId, 'pm_1');
      expect(request.idempotencyKey, isNot(firstKey));
      // Only the failed items are re-sent.
      expect(request.memberships.single.memberId, 'mem-new');
      // The card was NOT cleared or re-keyed — this is the same-card path.
      expect(cubit.state.cardAttempt, 0);
      // The retry cleared the failure, so the receipt now reads all-created.
      expect(cubit.state.failedItems, isEmpty);
      verifyNever(() => member.createMember(any()));
      verifyNever(
        () => memberships.recordWaiverSignature(
          waiverId: any(named: 'waiverId'),
          gymId: any(named: 'gymId'),
          memberId: any(named: 'memberId'),
          waiverVersionId: any(named: 'waiverVersionId'),
          signerName: any(named: 'signerName'),
        ),
      );
      expect(cubit.state.step, KioskSignupStep.results);
      await cubit.close();
    });

    test('two synchronous "Retry" taps are exactly ONE charge', () async {
      when(
        () => member.startMemberships(
          any(),
          receiveTimeout: any(named: 'receiveTimeout'),
        ),
      ).thenAnswer((_) async => _startResponse(failed: true));
      final cubit = await atReview();
      await cubit.pay();
      expect(cubit.state.step, KioskSignupStep.declined);
      clearInteractions(member);

      // `retrySameCard` re-fires `pay()`, whose guard drops the second tap.
      cubit.retrySameCard();
      cubit.retrySameCard();
      await _settle();

      verify(
        () => member.startMemberships(
          any(),
          receiveTimeout: any(named: 'receiveTimeout'),
        ),
      ).called(1);
      await cubit.close();
    });

    test('"Get help at the desk" is a handoff — it stops, keeping the state',
        () async {
      when(
        () => member.startMemberships(
          any(),
          receiveTimeout: any(named: 'receiveTimeout'),
        ),
      ).thenAnswer((_) async => _startResponse(failed: true));
      final cubit = await atReview();
      await cubit.pay();
      cubit.getHelpAtDesk();

      expect(cubit.state.step, KioskSignupStep.stop);
      expect(cubit.state.stopReason, KioskSignupStopReason.cardDeclined);
      // Everything already committed stays committed.
      expect(cubit.state.payer.memberId, 'mem-new');
      expect(cubit.state.signedWaiverIds, [waiverId]);
      verify(() => session.endFlow()).called(1);
      await cubit.close();
    });
  });

  group('the plan step', () {
    test('a gym with nothing sellable stops rather than showing an empty grid',
        () async {
      when(() => memberships.listPlans(any()))
          .thenAnswer((_) async => <MembershipPlanResponse>[]);
      final cubit = build();
      await _settle();
      cubit.submitDetails(
        firstName: 'Marcus',
        lastName: 'Bell',
        email: 'marcus.bell@gmail.com',
      );
      await cubit.submitExtraDetails();
      cubit.continueToPlans();

      expect(cubit.state.step, KioskSignupStep.stop);
      expect(cubit.state.stopReason, KioskSignupStopReason.noPlansOffered);
      verify(() => session.endFlow()).called(1);
      await cubit.close();
    });

    test('a failed catalogue read is a RETRYABLE stop that holds the flow',
        () async {
      when(() => memberships.listPlans(any())).thenThrow(Exception('down'));
      final cubit = build();
      await _settle();
      cubit.submitDetails(
        firstName: 'Marcus',
        lastName: 'Bell',
        email: 'marcus.bell@gmail.com',
      );
      await cubit.submitExtraDetails();
      cubit.continueToPlans();
      await _settle();

      expect(cubit.state.step, KioskSignupStep.stop);
      expect(cubit.state.stopReason, KioskSignupStopReason.plansUnavailable);
      expect(cubit.state.stopReason!.isRetryable, isTrue);
      // A retryable stop holds the count.
      verifyNever(() => session.endFlow());

      when(() => memberships.listPlans(any()))
          .thenAnswer((_) async => [_recurringPlan()]);
      cubit.stopRetry();
      await _settle();
      expect(cubit.state.step, KioskSignupStep.plans);
      expect(cubit.state.plans, hasLength(1));
      await cubit.close();
    });
  });

  group('waivers', () {
    test('a stale 409 reloads the body and the re-sign succeeds', () async {
      var attempt = 0;
      when(
        () => memberships.recordWaiverSignature(
          waiverId: any(named: 'waiverId'),
          gymId: any(named: 'gymId'),
          memberId: any(named: 'memberId'),
          waiverVersionId: any(named: 'waiverVersionId'),
          signerName: any(named: 'signerName'),
        ),
      ).thenAnswer((_) async {
        if (attempt++ == 0) throw const WaiverStaleVersionException();
        return _MockSignatureResponse();
      });

      final cubit = build();
      cubit.submitDetails(
        firstName: 'Marcus',
        lastName: 'Bell',
        email: 'marcus.bell@gmail.com',
      );
      await cubit.submitExtraDetails();
      cubit.continueToPlans();
      cubit.selectPlan(planId);
      cubit.continueFromPlans();
      await _settle();

      await cubit.signWaiver(signerName: 'Marcus Bell');
      await _settle();
      expect(cubit.state.step, KioskSignupStep.waivers);
      expect(cubit.state.waiverStale, isTrue);
      expect(cubit.state.signedWaiverIds, isEmpty);
      verify(() => memberships.getWaiver(waiverId, gymId)).called(2);

      await cubit.signWaiver(signerName: 'Marcus Bell');
      expect(cubit.state.step, KioskSignupStep.card);
      expect(cubit.state.signedWaiverIds, [waiverId]);
      await cubit.close();
    });

    test('a signed waiver is never presented (or signed) twice', () async {
      final cubit = await atReview();
      clearInteractions(memberships);
      // The queue is rebuilt, but the committed signature skips the step.
      cubit.back();
      expect(cubit.state.step, KioskSignupStep.card);
      cubit.back();
      expect(cubit.state.step, KioskSignupStep.plans);
      cubit.continueFromPlans();
      await _settle();

      expect(cubit.state.step, KioskSignupStep.card);
      verifyNever(
        () => memberships.recordWaiverSignature(
          waiverId: any(named: 'waiverId'),
          gymId: any(named: 'gymId'),
          memberId: any(named: 'memberId'),
          waiverVersionId: any(named: 'waiverVersionId'),
          signerName: any(named: 'signerName'),
        ),
      );
      await cubit.close();
    });
  });

  group('Back out of the review', () {
    test('it hands the card step a genuinely EMPTY field', () async {
      final cubit = await atReview();
      expect(cubit.state.cardAttempt, 0);
      cubit.back();

      expect(cubit.state.step, KioskSignupStep.card);
      // The Stripe `CardField`'s web platform view is CACHED across mounts, so
      // without a NEW key the returning step re-shows the typed card while its
      // `_complete` flag resets — leaving "Review" permanently untappable.
      expect(cubit.state.cardAttempt, 1);
      // And state agrees with the screen: no card, no key, no priced review.
      expect(cubit.state.paymentMethodId, isNull);
      expect(cubit.state.cardBrand, isNull);
      expect(cubit.state.cardLast4, isNull);
      expect(cubit.state.idempotencyKey, isNull);
      expect(cubit.state.preview, isNull);

      clearInteractions(member);
      cubit.submitCard(paymentMethodId: 'pm_2', brand: 'visa', last4: '1881');
      await _settle();
      expect(cubit.state.step, KioskSignupStep.review);
      expect(cubit.state.preview, isNotNull);
      verifyNever(() => member.createMember(any()));
      await cubit.close();
    });
  });

  group('the review preview', () {
    test('a waiver gate on the preview routes back to the waiver step',
        () async {
      final cubit = build();
      cubit.submitDetails(
        firstName: 'Marcus',
        lastName: 'Bell',
        email: 'marcus.bell@gmail.com',
      );
      await cubit.submitExtraDetails();
      cubit.continueToPlans();
      cubit.selectPlan(planId);
      cubit.continueFromPlans();
      await _settle();
      await cubit.signWaiver(signerName: 'Marcus Bell');

      when(() => member.previewStartMemberships(any())).thenThrow(
        const WaiverGateException(
          message: 'unsigned',
          unsigned: [
            WaiverGateItem(
              memberId: 'mem-new',
              waiverId: waiverId,
              name: 'Liability Waiver',
            ),
          ],
        ),
      );
      cubit.submitCard(paymentMethodId: 'pm_1');
      await _settle();

      expect(cubit.state.step, KioskSignupStep.waivers);
      expect(cubit.state.signedWaiverIds, isEmpty);
      verifyNever(() => session.endFlow());
      await cubit.close();
    });

    test('a failed preview is a RETRYABLE stop, never a blank screen',
        () async {
      when(() => member.previewStartMemberships(any()))
          .thenThrow(const NetworkException('timeout'));
      final cubit = build();
      cubit.submitDetails(
        firstName: 'Marcus',
        lastName: 'Bell',
        email: 'marcus.bell@gmail.com',
      );
      await cubit.submitExtraDetails();
      cubit.continueToPlans();
      cubit.selectPlan(planId);
      cubit.continueFromPlans();
      await _settle();
      await cubit.signWaiver(signerName: 'Marcus Bell');
      cubit.submitCard(paymentMethodId: 'pm_1');
      await _settle();

      expect(cubit.state.step, KioskSignupStep.stop);
      expect(cubit.state.stopReason, KioskSignupStopReason.previewFailed);
      expect(cubit.state.stopReason!.isRetryable, isTrue);
      verifyNever(() => session.endFlow());

      when(() => member.previewStartMemberships(any()))
          .thenAnswer((_) async => _preview());
      cubit.stopRetry();
      await _settle();
      expect(cubit.state.step, KioskSignupStep.review);
      expect(cubit.state.preview, isNotNull);
      await cubit.close();
    });
  });

  group('the money the review states', () {
    test('due today is one-time + due-now, and a zero one-time is not "two '
        'charges"', () async {
      when(() => member.previewStartMemberships(any())).thenAnswer(
        (_) async => MemberMembershipsStartPreview(
          oneTime: _invoice(0),
          dueNow: _invoice(14900),
          recurring: _invoice(14900),
        ),
      );
      final cubit = await atReview();

      expect(cubit.state.dueTodayMinorUnits, 14900);
      // The predicate tests the AMOUNTS: a $0 one-time invoice exists but
      // carries nothing, so calling it two charges would be a lie.
      expect(cubit.state.chargedTwiceToday, isFalse);
      await cubit.close();
    });

    test('a genuinely mixed cart says two charges', () async {
      when(() => member.previewStartMemberships(any())).thenAnswer(
        (_) async => MemberMembershipsStartPreview(
          oneTime: _invoice(6000),
          dueNow: _invoice(14900),
          recurring: _invoice(14900),
        ),
      );
      final cubit = await atReview();

      expect(cubit.state.dueTodayMinorUnits, 20900);
      expect(cubit.state.chargedTwiceToday, isTrue);
      await cubit.close();
    });
  });
}

/// Let the cubit's `unawaited` reads settle.
Future<void> _settle() => Future<void>.delayed(Duration.zero);

/// The recurring plan's one-time twin — same ids and price, so only the plan
/// TYPE differs.
MembershipPlanResponse _oneTimePlan() => MembershipPlanResponse(
      planId: 'plan-1',
      gymId: 'gym-1',
      planName: 'Day pass',
      imageUrl: 'https://cdn/plan.png',
      planType: PlanType.oneTime,
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

MembershipPlanResponse _recurringPlan() => MembershipPlanResponse(
      planId: 'plan-1',
      gymId: 'gym-1',
      planName: 'Unlimited',
      imageUrl: 'https://cdn/plan.png',
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

WaiverResponse _waiver() => WaiverResponse(
      waiverId: 'waiver-1',
      gymId: 'gym-1',
      name: 'Liability Waiver & Release',
      waiverType: WaiverType.custom,
      currentVersionId: 'ver-3',
      currentVersionNumber: 3,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      currentVersion: WaiverVersionResponse(
        versionId: 'ver-3',
        waiverId: 'waiver-1',
        gymId: 'gym-1',
        versionNumber: 3,
        body: 'I agree, {{signer_name}}.',
        contentHash: 'hash',
        createdAt: DateTime.utc(2026),
      ),
    );

PreviewInvoice _invoice(int total) => PreviewInvoice(
      amountDue: total,
      subtotal: total,
      total: total,
      currency: 'usd',
      lines: [
        PreviewInvoiceLine(
          amount: total,
          discountedAmount: total,
          description: 'Unlimited',
        ),
      ],
    );

MemberMembershipsStartPreview _preview() => MemberMembershipsStartPreview(
      dueNow: _invoice(14900),
      recurring: _invoice(14900),
    );

MemberMembershipsStartResponse _startResponse({bool failed = false}) =>
    MemberMembershipsStartResponse(
      chargeCount: 1,
      multipleCharges: false,
      results: [
        MemberMembershipsStartResultItem(
          memberId: 'mem-new',
          planId: 'plan-1',
          planType: PlanType.recurring,
          status: failed
              ? MemberMembershipsStartStatus.failed
              : MemberMembershipsStartStatus.created,
          itemId: failed ? null : 'item-1',
          error: failed ? 'card_declined' : null,
        ),
      ],
    );
