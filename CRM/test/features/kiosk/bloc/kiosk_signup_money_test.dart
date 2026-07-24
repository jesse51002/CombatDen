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
/// pay / declined / welcome terminals.
///
/// Every test here exists because getting it wrong charges a real card twice,
/// takes money and shows a blank screen, or leaks the session's flow count so
/// the iPad never signs itself out at its 12-hour lockout.
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
    when(() => member.createMember(any())).thenAnswer((_) async => 'mem-new');
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

  KioskSignupCubit build({
    Duration declineCooldown = kKioskSignupDeclineCooldown,
  }) =>
      KioskSignupCubit(
        memberRepository: member,
        membershipsRepository: memberships,
        membersListRepository: membersList,
        session: session,
        gymId: gymId,
        now: () => t0,
        // Every key is distinct, so "a NEW key" is a real assertion rather
        // than an artefact of a constant stub.
        uuid: () => 'key-${++uuidSeq}',
        declineCooldown: declineCooldown,
      );

  /// Walk a solo signup from the first field to the review, ready to pay.
  Future<KioskSignupCubit> atReview({
    Duration declineCooldown = kKioskSignupDeclineCooldown,
  }) async {
    final cubit = build(declineCooldown: declineCooldown);
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

    test('the PAY call sends the fresh card with set_default for a recurring '
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
      // The CRM wizard deliberately sends NO card for a recurring cart (it
      // reuses the payer's saved default). The kiosk has no saved default to
      // reuse — the backend rejects a recurring start without one.
      expect(payment.paymentMethodId, 'pm_1');
      expect(payment.setDefault, isTrue);
      expect(request.paidWithCash, isFalse);
      expect(cubit.state.step, KioskSignupStep.welcome);
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

      // The outcome of that attempt is unknown, so a second pay must not
      // re-post it: an auto-retry is the one action that could double-charge.
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
    test('201 lands on welcome and releases the flow exactly once', () async {
      final cubit = await atReview();
      verifyNever(() => session.endFlow());
      await cubit.pay();

      expect(cubit.state.step, KioskSignupStep.welcome);
      verify(() => session.endFlow()).called(1);
      await cubit.close();
      // Still exactly once after teardown — the latch holds.
      verifyNever(() => session.endFlow());
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
      // The server is authoritative: a waiver it calls unsigned is dropped
      // from our own signed set, or the step would skip it and loop.
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
    test('a 207 declines, holds the flow count, and offers a retry', () async {
      when(
        () => member.startMemberships(
          any(),
          receiveTimeout: any(named: 'receiveTimeout'),
        ),
      ).thenAnswer((_) async => _startResponse(failed: true));
      final cubit = await atReview();
      await cubit.pay();

      expect(cubit.state.step, KioskSignupStep.declined);
      expect(cubit.state.declineCount, 1);
      expect(cubit.state.failedItems, hasLength(1));
      // The member is still standing there: a decline is NOT an exit.
      verifyNever(() => session.endFlow());
      await cubit.close();
    });

    test('the retry uses a NEW key and never re-creates or re-signs anything',
        () async {
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
      // The element is cleared: the retry must carry a genuinely new card.
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
      // Members, signatures and plans are already committed — a retry
      // re-executes the CHARGE only.
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

    test('each attempt bumps cardAttempt, so the card field is re-keyed and '
        'mounts a fresh, empty Stripe iframe', () async {
      when(
        () => member.startMemberships(
          any(),
          receiveTimeout: any(named: 'receiveTimeout'),
        ),
      ).thenAnswer((_) async => _startResponse(failed: true));
      final cubit = await atReview(declineCooldown: Duration.zero);
      // First attempt is nonce 0 — the initial field.
      expect(cubit.state.cardAttempt, 0);

      await cubit.pay();
      expect(cubit.state.step, KioskSignupStep.declined);
      cubit.retryCard();
      // A retry mints a NEW field identity: the widget keys off this nonce
      // (`ValueKey('kiosk-card-$cardAttempt')`), so the returning card step
      // mounts a brand-new iframe instead of the one still holding the decline.
      expect(cubit.state.cardAttempt, 1);

      cubit.submitCard(paymentMethodId: 'pm_2', brand: 'visa', last4: '1881');
      await _settle();
      await cubit.pay();
      cubit.retryCard();
      expect(cubit.state.cardAttempt, 2);
      await cubit.close();
    });

    test('a decline is NEVER terminal — the member keeps trying, uncapped',
        () async {
      when(
        () => member.startMemberships(
          any(),
          receiveTimeout: any(named: 'receiveTimeout'),
        ),
      ).thenAnswer((_) async => _startResponse(failed: true));
      // The cooldown is a separate control with its own test; this one is
      // about the ABSENCE of a cap, so it runs with the wait disabled.
      final cubit = await atReview(declineCooldown: Duration.zero);

      await cubit.pay();
      // From here on, nothing already committed may be touched again.
      clearInteractions(member);
      clearInteractions(memberships);
      final keys = <String>[cubit.state.idempotencyKey!];
      for (var i = 2; i <= 7; i++) {
        expect(cubit.state.step, KioskSignupStep.declined);
        await _retryAndPay(cubit, 'pm_$i');
        keys.add(cubit.state.idempotencyKey!);
      }

      // Well past the old three-strike ending: still retryable, never a stop.
      expect(cubit.state.step, KioskSignupStep.declined);
      expect(cubit.state.declineCount, 7);
      expect(cubit.state.stopReason, isNull);
      // Every retry is a genuinely new attempt.
      expect(keys.toSet().length, keys.length);
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
      // The flow count is NOT released on `declined` — the member is standing
      // right there and is not finished.
      verifyNever(() => session.endFlow());
      await cubit.close();
    });

    test('a run of declines engages the 30s cooldown, and it gates PAY',
        () async {
      when(
        () => member.startMemberships(
          any(),
          receiveTimeout: any(named: 'receiveTimeout'),
        ),
      ).thenAnswer((_) async => _startResponse(failed: true));
      final cubit = await atReview();

      await cubit.pay();
      expect(cubit.state.retryCooldown, 0);
      await _retryAndPay(cubit, 'pm_2');
      expect(cubit.state.retryCooldown, 0);
      await _retryAndPay(cubit, 'pm_3');

      // The third consecutive decline starts the wait.
      expect(
        cubit.state.retryCooldown,
        kKioskSignupDeclineCooldown.inSeconds,
      );
      expect(cubit.state.step, KioskSignupStep.declined);
      // Walking back to the card step and returning does NOT clear it: the
      // countdown lives on the cubit, not on the widget.
      cubit.retryCard();
      cubit.submitCard(paymentMethodId: 'pm_4', brand: 'visa', last4: '4242');
      await _settle();
      expect(cubit.state.retryCooldown, greaterThan(0));

      // Three attempts have left the device; Pay is inert while the wait
      // runs, so a fourth does not.
      await cubit.pay();
      verify(
        () => member.startMemberships(
          any(),
          receiveTimeout: any(named: 'receiveTimeout'),
        ),
      ).called(3);
      expect(cubit.state.step, KioskSignupStep.review);
      await cubit.close();
    });

    test('the cooldown elapses on its own and Pay comes back', () async {
      when(
        () => member.startMemberships(
          any(),
          receiveTimeout: any(named: 'receiveTimeout'),
        ),
      ).thenAnswer((_) async => _startResponse(failed: true));
      final cubit = await atReview(
        declineCooldown: const Duration(seconds: 1),
      );
      await cubit.pay();
      await _retryAndPay(cubit, 'pm_2');
      await _retryAndPay(cubit, 'pm_3');
      expect(cubit.state.retryCooldown, 1);

      await Future<void>.delayed(const Duration(milliseconds: 1300));
      expect(cubit.state.retryCooldown, 0);

      await _retryAndPay(cubit, 'pm_4');
      expect(cubit.state.step, KioskSignupStep.declined);
      expect(cubit.state.declineCount, 4);
      await cubit.close();
    });

    test('a successful charge resets the consecutive-decline run', () async {
      when(
        () => member.startMemberships(
          any(),
          receiveTimeout: any(named: 'receiveTimeout'),
        ),
      ).thenAnswer((_) async => _startResponse(failed: true));
      final cubit = await atReview();
      await cubit.pay();
      expect(cubit.state.declineCount, 1);

      when(
        () => member.startMemberships(
          any(),
          receiveTimeout: any(named: 'receiveTimeout'),
        ),
      ).thenAnswer((_) async => _startResponse());
      await _retryAndPay(cubit, 'pm_2');

      expect(cubit.state.step, KioskSignupStep.welcome);
      expect(cubit.state.declineCount, 0);
      expect(cubit.state.retryCooldown, 0);
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
      // The member is still standing there — the count is NOT released.
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
      // Still on the waiver, with the republished body reloaded and flagged.
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
      // Back to the plan, forward again: the queue is rebuilt but the
      // signature is committed, so the step is skipped entirely.
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
      // The predicate tests the AMOUNTS: a $0 one-time invoice EXISTS but
      // carries nothing, and calling that two charges would be a lie about
      // the member's own statement.
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

/// "Try another card" → a fresh card → Pay.
Future<void> _retryAndPay(KioskSignupCubit cubit, String pm) async {
  cubit.retryCard();
  cubit.submitCard(paymentMethodId: pm, brand: 'visa', last4: '4242');
  await _settle();
  await cubit.pay();
}

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
