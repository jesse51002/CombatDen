import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:crm/core/errors/exceptions.dart';
import 'package:crm/features/kiosk/bloc/kiosk_flow_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_session_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_state.dart';
import 'package:crm/features/member_details/data/models/authorized_payer_waiver.dart';
import 'package:crm/features/member_details/data/models/duplicate_member_match.dart';
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
import 'package:crm/features/member_details/data/repositories/member_repository.dart';
import 'package:crm/features/members_list/data/models/crm_members_list_request.dart';
import 'package:crm/features/members_list/data/models/crm_members_list_response.dart';
import 'package:crm/features/members_list/data/models/member_row.dart';
import 'package:crm/features/members_list/data/models/members_list_filters.dart';
import 'package:crm/features/members_list/data/models/members_list_view.dart';
import 'package:crm/features/members_list/data/models/membership_status.dart';
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

/// The kiosk signup's GROUP half — the roster, the existing-member match, the
/// per-person link run, and the money path over more than one person.
///
/// Every test here exists because getting it wrong either charges the wrong
/// people, hands the backend a member nobody authorized, or dead-ends a parent
/// halfway through signing up their family.
void main() {
  const gymId = 'gym-1';
  const soloPlan = 'plan-1';
  const kidsPlan = 'plan-2';
  const waiverId = 'waiver-1';
  final t0 = DateTime.utc(2026, 1, 1, 18);

  late _MockMemberRepository member;
  late _MockMembershipsRepository memberships;
  late _MockMembersListRepository membersList;
  late _MockKioskSessionCubit session;
  late int uuidSeq;
  late int createSeq;

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
    registerFallbackValue(
      const CrmMembersListRequest(
        gymId: gymId,
        view: MembersListView.all,
        filters: MembersListFilters(),
        startIndex: 0,
        count: 8,
      ),
    );
  });

  setUp(() {
    member = _MockMemberRepository();
    memberships = _MockMembershipsRepository();
    membersList = _MockMembersListRepository();
    session = _MockKioskSessionCubit();
    uuidSeq = 0;
    createSeq = 0;

    when(() => memberships.listPlans(any()))
        .thenAnswer((_) async => [_recurringPlan(), _kidsPlan()]);
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
    // Distinct ids per create, so "which member ended up in the cart" is a
    // real assertion rather than an artefact of a constant stub.
    when(() => member.createMember(any()))
        .thenAnswer((_) async => 'mem-${++createSeq}');
    when(() => member.updateMember(any(), any()))
        .thenAnswer((_) async => _MockManagementResponse());
    when(() => member.getAuthorizedPayerWaiver(any()))
        .thenAnswer((_) async => _payerAuthWaiver());
    when(
      () => member.linkMemberAccount(
        any(),
        payerMemberId: any(named: 'payerMemberId'),
        waiverVersionId: any(named: 'waiverVersionId'),
        signerName: any(named: 'signerName'),
        consentAcknowledged: any(named: 'consentAcknowledged'),
      ),
    ).thenAnswer((_) async {});
    when(() => member.previewStartMemberships(any()))
        .thenAnswer((_) async => _preview());
    when(
      () => member.startMemberships(
        any(),
        receiveTimeout: any(named: 'receiveTimeout'),
      ),
    ).thenAnswer((_) async => _startResponse());
    when(() => membersList.getMembersList(any()))
        .thenAnswer((_) async => _page(const []));
  });

  KioskSignupCubit build() => KioskSignupCubit(
        memberRepository: member,
        membershipsRepository: memberships,
        membersListRepository: membersList,
        session: session,
        gymId: gymId,
        now: () => t0,
        uuid: () => 'key-${++uuidSeq}',
      );

  /// The payer, created, standing on the roster.
  Future<KioskSignupCubit> atRoster() async {
    final cubit = build();
    cubit.submitDetails(
      firstName: 'Marcus',
      lastName: 'Bell',
      email: 'marcus.bell@gmail.com',
    );
    await cubit.submitExtraDetails();
    expect(cubit.state.step, KioskSignupStep.people);
    return cubit;
  }

  /// Add one brand-new payee and skip their optional block.
  Future<void> addPayee(KioskSignupCubit cubit, String firstName) async {
    await cubit.addPerson(
      firstName: firstName,
      lastName: 'Bell',
      email: '${firstName.toLowerCase()}.bell@gmail.com',
    );
    expect(cubit.state.step, KioskSignupStep.personDetails);
    cubit.skipPersonDetails();
  }

  /// The roster's usual second person — Ella, `mem-2`.
  Future<void> addElla(KioskSignupCubit cubit) => addPayee(cubit, 'Ella');

  /// Walk the whole two-person group from the roster to the review.
  Future<void> walkGroupToReview(KioskSignupCubit cubit) async {
    cubit.continueToPlans();
    cubit.selectPlan(soloPlan);
    cubit.continueFromPlans();
    cubit.selectPlan(kidsPlan);
    cubit.continueFromPlans();
    await _settle();
    // The run opens on the payee's payer-auth agreement (ruling 9).
    expect(cubit.state.payerAuthPending, isTrue);
    await cubit.signPayerAuth(signerName: 'Marcus Bell');
    await _settle();
    await cubit.signWaiver(signerName: 'Marcus Bell');
    await _settle();
    await cubit.signWaiver(signerName: 'Marcus Bell');
    expect(cubit.state.step, KioskSignupStep.card);
    cubit.submitCard(paymentMethodId: 'pm_1', brand: 'visa', last4: '4242');
    await _settle();
    expect(cubit.state.step, KioskSignupStep.review);
  }

  group('both duplicates end in an offer, through different screens', () {
    test('a PAYEE 409 offers the roster match; a PAYER 409 offers "is this you?"',
        () async {
      // ── the payee half ──
      final cubit = await atRoster();
      when(() => member.createMember(any())).thenThrow(
        const DuplicateMemberException([
          DuplicateMemberMatch(
            memberId: 'mem-ella-existing',
            firstName: 'Ella',
            lastName: 'Bell',
            email: 'ella.bell@gmail.com',
          ),
        ]),
      );
      await cubit.addPerson(
        firstName: 'Ella',
        lastName: 'Bell',
        email: 'ella.bell@gmail.com',
      );

      // An OFFER, not a stop: a payee pays nothing, so reusing their existing
      // account is the right answer.
      expect(cubit.state.step, KioskSignupStep.match);
      expect(cubit.state.stopReason, isNull);
      expect(cubit.state.matchCandidate?.memberId, 'mem-ella-existing');
      // Nothing is on the roster yet — the draft is held off it until the
      // backend has made (or matched) them.
      expect(cubit.state.persons.length, 1);
      expect(cubit.state.pendingPayee?.firstName, 'Ella');
      await cubit.close();

      // ── the payer half, same 409 ──
      final payer = build();
      payer.submitDetails(
        firstName: 'Ella',
        lastName: 'Bell',
        email: 'ella.bell@gmail.com',
      );
      await payer.submitExtraDetails();

      // ALSO an offer, through a DIFFERENT screen. A payee's match is the
      // roster's "is this her?"; the payer's is "is this you?", confirming
      // their own account back to them. Both routes reuse an existing account
      // rather than making a second one — the lane is self-serve for existing
      // members too, and whoever pays types a fresh card either way.
      expect(payer.state.step, KioskSignupStep.payerMatch);
      expect(payer.state.stopReason, isNull);
      expect(payer.state.matchCandidate?.memberId, 'mem-ella-existing');
      await payer.close();
    });

    test('"Yes, that\'s her" adopts the existing member and skips their '
        'details', () async {
      final cubit = await atRoster();
      when(() => member.createMember(any())).thenThrow(
        const DuplicateMemberException([
          DuplicateMemberMatch(
            memberId: 'mem-ella-existing',
            firstName: 'Ella',
            lastName: 'Bell',
            email: 'ella.bell@gmail.com',
          ),
        ]),
      );
      await cubit.addPerson(
        firstName: 'Elle',
        lastName: 'Bel',
        email: 'ella.bell@gmail.com',
      );
      clearInteractions(member);
      cubit.confirmMatch();

      final ella = cubit.state.persons[1];
      expect(ella.memberId, 'mem-ella-existing');
      expect(ella.wasExisting, isTrue);
      // The gym's record wins over the typo that produced the match.
      expect(ella.firstName, 'Ella');
      expect(ella.lastName, 'Bell');
      // NOTHING of theirs is carried into this signup's state — a lobby iPad
      // never holds, prints or overwrites a record the kiosk does not own.
      expect(ella.dob, isNull);
      expect(ella.address, isNull);
      expect(ella.ecName, isNull);
      expect(ella.detailsStatus, KioskSignupDetailsStatus.none);
      // Adopting creates nothing.
      verifyNever(() => member.createMember(any()));
      // And there is no details pass for them at all: a form that can only
      // ever ask for what the gym already has is not worth a screen.
      expect(cubit.state.step, KioskSignupStep.people);
      verifyNever(() => member.updateMember(any(), any()));
      await cubit.close();
    });

    test('"No — different person" re-creates with allowDuplicate: true',
        () async {
      final cubit = await atRoster();
      when(() => member.createMember(any())).thenThrow(
        const DuplicateMemberException([
          DuplicateMemberMatch(
            memberId: 'mem-ella-existing',
            firstName: 'Ella',
            lastName: 'Bell',
          ),
        ]),
      );
      await cubit.addPerson(
        firstName: 'Ella',
        lastName: 'Bell',
        email: 'ella.bell@gmail.com',
      );
      expect(cubit.state.step, KioskSignupStep.match);

      when(() => member.createMember(any()))
          .thenAnswer((_) async => 'mem-ella-new');
      await cubit.rejectMatch();

      final request = verify(() => member.createMember(captureAny()))
          .captured
          .last as MembersManagementCreateRequest;
      expect(request.allowDuplicate, isTrue);
      expect(request.firstName, 'Ella');
      expect(cubit.state.persons[1].memberId, 'mem-ella-new');
      expect(cubit.state.persons[1].wasExisting, isFalse);
      await cubit.close();
    });
  });

  group('link before start', () {
    test('every payee is linked BEFORE the start request is built', () async {
      final cubit = await atRoster();
      await addElla(cubit);
      await walkGroupToReview(cubit);
      await cubit.pay();

      // The start call never links, so the ordering has to be guaranteed here.
      verifyInOrder([
        () => member.linkMemberAccount(
              'mem-2',
              payerMemberId: 'mem-1',
              waiverVersionId: 'payer-ver-1',
              signerName: 'Marcus Bell',
              consentAcknowledged: true,
            ),
        () => member.previewStartMemberships(any()),
        () => member.startMemberships(
              any(),
              receiveTimeout: kKioskSignupStartTimeout,
            ),
      ]);
      expect(cubit.state.step, KioskSignupStep.results);
      await cubit.close();
    });

    test('an UNLINKED payee means no request is assembled at all, and neither '
        'dead end is silent', () async {
      final cubit = await atRoster();
      await addElla(cubit);
      expect(cubit.state.everyPayeeLinked, isFalse);

      // Jump the card straight onto a roster that has not been through the
      // link run: neither the preview nor the charge may be assembled.
      cubit.submitCard(paymentMethodId: 'pm_1');
      await _settle();
      verifyNever(() => member.previewStartMemberships(any()));

      // **Never a permanent spinner.** The review renders its spinner off
      // `preview == null`, so a request that cannot even be ASSEMBLED has to
      // land on the same retryable stop a FAILED preview does — a kiosk screen
      // with no figure, no countdown and no way on is fatal.
      expect(cubit.state.step, KioskSignupStep.stop);
      expect(cubit.state.stopReason, KioskSignupStopReason.previewFailed);
      expect(cubit.state.stopReason!.isRetryable, isTrue);
      expect(cubit.state.stopCountdown, kKioskSignupStopHold.inSeconds);

      await cubit.pay();
      verifyNever(
        () => member.startMemberships(
          any(),
          receiveTimeout: any(named: 'receiveTimeout'),
        ),
      );
      // And Pay with nothing to send is a handoff WITH a clock, never a silent
      // return: `retrySameCard` cancels the popup's own return countdown before
      // it calls `pay()`, so a quiet return there parks a shared iPad on a
      // popup with no countdown and no escape. Nothing was sent, so "nothing
      // was charged" is exactly true.
      expect(cubit.state.step, KioskSignupStep.stop);
      expect(cubit.state.stopReason, KioskSignupStopReason.paymentFailed);
      expect(cubit.state.stopCountdown, kKioskSignupStopHold.inSeconds);
      await cubit.close();
    });
  });

  group('a retry re-sends only what did NOT start', () {
    test('a [created, unknown] partial re-sends ONLY the unconfirmed '
        'membership, never the one that already started', () async {
      final cubit = await atRoster();
      await addElla(cubit);
      await walkGroupToReview(cubit);

      // The payer's membership was created; the child's came back with a status
      // this client does not recognise, which `MemberMembershipsStartStatus`
      // parses to `unknown` — **neither created nor failed.** A retry set keyed
      // on FAILURES is therefore empty here, and an empty set that falls back
      // to "then send everything" re-charges the membership that already
      // started, under the fresh idempotency key every retry mints — which the
      // backend's `ON CONFLICT (idempotency_key)` guard cannot dedupe.
      when(
        () => member.startMemberships(
          any(),
          receiveTimeout: any(named: 'receiveTimeout'),
        ),
      ).thenAnswer((_) async => _startResponse(unknownMemberId: 'mem-2'));
      await cubit.pay();

      // The partial receipt, where Retry is live.
      expect(cubit.state.step, KioskSignupStep.results);
      expect(cubit.state.allCreated, isFalse);
      // The display set and the retry set are deliberately NOT the same set:
      // nothing was refused, and one row is still unconfirmed.
      expect(cubit.state.failedItems, isEmpty);
      expect(cubit.state.retryMemberIds, {'mem-2'});
      expect(cubit.state.canRetryStart, isTrue);

      when(
        () => member.startMemberships(
          any(),
          receiveTimeout: any(named: 'receiveTimeout'),
        ),
      ).thenAnswer((_) async => _startResponse(only: 'mem-2'));
      cubit.retrySameCard();
      await _settle();

      final sent = verify(
        () => member.startMemberships(
          captureAny(),
          receiveTimeout: any(named: 'receiveTimeout'),
        ),
      ).captured.cast<MemberMembershipsStartRequest>();
      expect(sent.length, 2);
      // **The double-charge guard.** One item, and not the payer's.
      expect(sent.last.memberships.map((m) => m.memberId).toList(), ['mem-2']);
      expect(sent.last.idempotencyKey, isNot(sent.first.idempotencyKey));
      // The same card, never re-typed, and nothing else re-executed.
      expect(sent.last.payment?.paymentMethodId, 'pm_1');
      verify(() => member.createMember(any())).called(2);
      verify(
        () => member.linkMemberAccount(
          any(),
          payerMemberId: any(named: 'payerMemberId'),
          waiverVersionId: any(named: 'waiverVersionId'),
          signerName: any(named: 'signerName'),
          consentAcknowledged: any(named: 'consentAcknowledged'),
        ),
      ).called(1);
      // The merge folded the retry into the first response, so the receipt
      // still lists both memberships — and now reads all-created.
      expect(cubit.state.startItems, hasLength(2));
      expect(cubit.state.allCreated, isTrue);
      await cubit.close();
    });

    test('an ALL-CREATED receipt has nothing to retry: Retry posts nothing and '
        'leaves the receipt (and its clock) alone', () async {
      final cubit = await atRoster();
      await addElla(cubit);
      await walkGroupToReview(cubit);
      await cubit.pay();

      expect(cubit.state.step, KioskSignupStep.results);
      expect(cubit.state.allCreated, isTrue);
      expect(cubit.state.retryMemberIds, isEmpty);
      expect(cubit.state.canRetryStart, isFalse);
      final countdown = cubit.state.popupCountdown;
      final key = cubit.state.idempotencyKey;

      // The all-created receipt offers `Next`, not Retry — but the CUBIT is
      // the guard: re-firing the charge from a screen where every membership
      // already started re-posted the WHOLE cart under a new key.
      cubit.retrySameCard();
      await _settle();

      verify(
        () => member.startMemberships(
          any(),
          receiveTimeout: any(named: 'receiveTimeout'),
        ),
      ).called(1);
      expect(cubit.state.step, KioskSignupStep.results);
      // The retry never began, so it must not have cancelled the clock that
      // takes the iPad home, nor minted a stray key.
      expect(cubit.state.popupCountdown, countdown);
      expect(cubit.state.idempotencyKey, key);
      await cubit.close();
    });

    test('a partial retry RE-PRICES against the same filtered items, so the '
        'paying screen cannot state the whole cart\'s amount', () async {
      final cubit = await atRoster();
      await addElla(cubit);
      await walkGroupToReview(cubit);

      when(
        () => member.startMemberships(
          any(),
          receiveTimeout: any(named: 'receiveTimeout'),
        ),
      ).thenAnswer((_) async => _startResponse(failedMemberId: 'mem-2'));
      await cubit.pay();
      expect(cubit.state.step, KioskSignupStep.results);

      cubit.retrySameCard();
      // The full-cart figure is dropped the instant the retry starts: the
      // paying screen states `dueTodayMinorUnits` as what is being taken, and
      // this retry takes only the child's membership.
      expect(cubit.state.preview, isNull);
      await _settle();

      final previews = verify(
        () => member.previewStartMemberships(captureAny()),
      ).captured.cast<MemberMembershipsStartRequest>();
      expect(previews, hasLength(2));
      // The review priced BOTH memberships...
      expect(previews.first.memberships, hasLength(2));
      // ...and the retry re-prices exactly what it re-sends.
      expect(
        previews.last.memberships.map((m) => m.memberId).toList(),
        ['mem-2'],
      );
      expect(cubit.state.preview, isNotNull);
      await cubit.close();
    });
  });

  group('consent is asked only of the people being charged', () {
    test('a payee who SKIPPED is never asked to authorize the payer, and the '
        'start no longer waits on their link', () async {
      final cubit = await atRoster();
      await addElla(cubit); // mem-2, index 1
      await addPayee(cubit, 'Theo'); // mem-3, index 2
      cubit.continueToPlans();

      cubit.selectPlan(soloPlan);
      cubit.continueFromPlans();
      expect(cubit.state.activePersonIndex, 1);
      cubit.selectPlan(kidsPlan);
      cubit.continueFromPlans();
      // Theo changes his mind halfway through the family signup.
      expect(cubit.state.activePersonIndex, 2);
      cubit.skipPlanForPerson();
      await _settle();

      // **The run walks only the people in the cart.** Theo is not one of
      // them, so asking him to authorize the payer for a membership he is not
      // buying would be consent taken from the wrong person for nothing.
      expect(cubit.state.waiverPersonQueue, [1, 0]);
      expect(cubit.state.payerAuthPending, isTrue);
      await cubit.signPayerAuth(signerName: 'Marcus Bell');
      await _settle();
      await cubit.signWaiver(signerName: 'Marcus Bell'); // Ella's liability
      await _settle();
      await cubit.signWaiver(signerName: 'Marcus Bell'); // the payer's own
      expect(cubit.state.step, KioskSignupStep.card);

      verify(() => member.getAuthorizedPayerWaiver('mem-2')).called(1);
      verifyNever(() => member.getAuthorizedPayerWaiver('mem-3'));
      verifyNever(
        () => member.linkMemberAccount(
          'mem-3',
          payerMemberId: any(named: 'payerMemberId'),
          waiverVersionId: any(named: 'waiverVersionId'),
          signerName: any(named: 'signerName'),
          consentAcknowledged: any(named: 'consentAcknowledged'),
        ),
      );
      expect(cubit.state.persons[2].linked, isFalse);

      // And an unlinked SKIPPED payee no longer blocks the charge. The backend
      // scopes the authorization rule to the request's own member ids
      // (`_check_links` in `memberships_start_validation.py`), and Theo is not
      // one of them — so demanding his link would dead-end the whole family.
      expect(cubit.state.everyPayeeLinked, isTrue);
      cubit.submitCard(paymentMethodId: 'pm_1');
      await _settle();

      final request = verify(() => member.previewStartMemberships(captureAny()))
          .captured
          .single as MemberMembershipsStartRequest;
      expect(
        request.memberships.map((m) => m.memberId).toList(),
        ['mem-1', 'mem-2'],
      );
      await cubit.close();
    });

    test('ticking a skipped person back on brings their link back with them',
        () async {
      final cubit = await atRoster();
      await addElla(cubit);
      cubit.setPersonTraining(1, false);

      // Nobody but the payer is in the cart, so nothing is owed for Ella.
      expect(cubit.state.everyPayeeLinked, isTrue);
      cubit.setPersonTraining(1, true);
      // Back in the cart, back to needing authorization — one predicate drives
      // both, so the two can never disagree.
      expect(cubit.state.everyPayeeLinked, isFalse);
      await cubit.close();
    });
  });

  group('the group cart', () {
    test('one item per TRAINING person, and a non-training payer is omitted',
        () async {
      final cubit = await atRoster();
      await addElla(cubit);
      // The parent pays but does not train.
      cubit.setPersonTraining(0, false);
      cubit.continueToPlans();
      // Only the payee picks — the plan step never opens for the payer.
      expect(cubit.state.activePersonIndex, 1);
      cubit.selectPlan(kidsPlan);
      cubit.continueFromPlans();
      await _settle();
      await cubit.signPayerAuth(signerName: 'Marcus Bell');
      await _settle();
      await cubit.signWaiver(signerName: 'Marcus Bell');
      expect(cubit.state.step, KioskSignupStep.card);
      cubit.submitCard(paymentMethodId: 'pm_1');
      await _settle();

      final request = verify(() => member.previewStartMemberships(captureAny()))
          .captured
          .single as MemberMembershipsStartRequest;
      // `payer_member_id` is identity-only server-side: the parent pays for
      // the child without buying anything of their own.
      expect(request.payerMemberId, 'mem-1');
      expect(request.memberships.single.memberId, 'mem-2');
      expect(request.memberships.single.quantity, 1);
      await cubit.close();
    });

    test('a two-person group sends one item each', () async {
      final cubit = await atRoster();
      await addElla(cubit);
      await walkGroupToReview(cubit);

      final request = verify(() => member.previewStartMemberships(captureAny()))
          .captured
          .single as MemberMembershipsStartRequest;
      expect(
        request.memberships.map((m) => m.memberId).toList(),
        ['mem-1', 'mem-2'],
      );
      expect(request.memberships.every((m) => m.quantity == 1), isTrue);
      await cubit.close();
    });

    test('a partial 207 retry carries ONLY the failed items and a new key',
        () async {
      final cubit = await atRoster();
      await addElla(cubit);
      await walkGroupToReview(cubit);

      // The payer's membership was created; the child's charge failed.
      when(
        () => member.startMemberships(
          any(),
          receiveTimeout: any(named: 'receiveTimeout'),
        ),
      ).thenAnswer((_) async => _startResponse(failedMemberId: 'mem-2'));
      await cubit.pay();
      // **A PARTIAL is the receipt, never the decline popup.** Money HAS moved
      // for the group that cleared, so "you haven't been charged" would be a
      // false statement about it — and the count stays HELD, because Retry is
      // live on that screen and a live charge must never run unheld.
      expect(cubit.state.step, KioskSignupStep.results);
      expect(cubit.state.allCreated, isFalse);
      verifyNever(() => session.endFlow());

      when(
        () => member.startMemberships(
          any(),
          receiveTimeout: any(named: 'receiveTimeout'),
        ),
      ).thenAnswer((_) async => _startResponse(only: 'mem-2'));
      cubit.retryCard();
      cubit.submitCard(paymentMethodId: 'pm_2');
      await _settle();
      await cubit.pay();

      final sent = verify(
        () => member.startMemberships(
          captureAny(),
          receiveTimeout: any(named: 'receiveTimeout'),
        ),
      ).captured.cast<MemberMembershipsStartRequest>();
      expect(sent.length, 2);
      // Nothing already created is re-sent: re-charging the payer's own
      // membership is exactly what a naive retry would do.
      expect(sent.last.memberships.single.memberId, 'mem-2');
      expect(sent.last.idempotencyKey, isNot(sent.first.idempotencyKey));
      expect(sent.last.payment?.paymentMethodId, 'pm_2');
      // No member, signature or link is ever re-executed by a retry.
      verify(() => member.createMember(any())).called(2);
      verify(
        () => member.linkMemberAccount(
          any(),
          payerMemberId: any(named: 'payerMemberId'),
          waiverVersionId: any(named: 'waiverVersionId'),
          signerName: any(named: 'signerName'),
          consentAcknowledged: any(named: 'consentAcknowledged'),
        ),
      ).called(1);
      await cubit.close();
    });

    test('a PARTIAL also offers NEXT — it carries on to the welcome, flags it, '
        'and releases the flow exactly once', () async {
      final cubit = await atRoster();
      await addElla(cubit);
      await walkGroupToReview(cubit);

      when(
        () => member.startMemberships(
          any(),
          receiveTimeout: any(named: 'receiveTimeout'),
        ),
      ).thenAnswer((_) async => _startResponse(failedMemberId: 'mem-2'));
      await cubit.pay();
      expect(cubit.state.step, KioskSignupStep.results);
      expect(cubit.state.allCreated, isFalse);
      // The retry ladder is UNTOUCHED — Next is additional, never a
      // replacement (founder ruling).
      expect(cubit.state.canRetryStart, isTrue);
      // Nothing released yet: Retry is live on that screen and a live charge
      // must never run with no flow held.
      verifyNever(() => session.endFlow());
      // Consume the one charge the receipt is the outcome of, so the check
      // after Next is about what NEXT sent.
      verify(
        () => member.startMemberships(
          any(),
          receiveTimeout: any(named: 'receiveTimeout'),
        ),
      ).called(1);

      cubit.nextFromResults();

      // **Not gated on `allCreated`.** A partial with only a way back held a
      // member who did not want to retry until the 60-second expiry, and the
      // people whose memberships DID start never reached the app push.
      expect(cubit.state.step, KioskSignupStep.welcome);
      // Nothing is re-sent by advancing: Next charges nothing at all.
      verifyNever(
        () => member.startMemberships(
          any(),
          receiveTimeout: any(named: 'receiveTimeout'),
        ),
      );
      // The welcome screen's front-desk line hangs off this flag: its greeting
      // is unconditional, so on a partial the screen would otherwise read as
      // "you're all set".
      expect(cubit.state.welcomeAfterPartial, isTrue);
      // The receipt held the count; Next is what releases it, exactly once.
      verify(() => session.endFlow()).called(1);
      await cubit.close();
      verifyNever(() => session.endFlow());
    });
  });

  group('the roster', () {
    test('remove drops an uncommitted person, and is gone once committed',
        () async {
      final cubit = await atRoster();
      await addElla(cubit);
      expect(cubit.state.canRemovePerson(1), isTrue);
      // The payer is removable too now, while nothing has committed against
      // them — see the dedicated no-payer group for what deleting them does.
      expect(cubit.state.canRemovePerson(0), isTrue);

      cubit.removePerson(1);
      expect(cubit.state.persons.length, 1);
      expect(cubit.state.isGroup, isFalse);

      // Add them back and take them through the link, which COMMITS them.
      await addElla(cubit);
      cubit.continueToPlans();
      cubit.selectPlan(soloPlan);
      cubit.continueFromPlans();
      cubit.selectPlan(kidsPlan);
      cubit.continueFromPlans();
      await _settle();
      await cubit.signPayerAuth(signerName: 'Marcus Bell');
      await _settle();

      // There is no unlink call, so removal stops being offered — and the
      // method is inert even if something calls it anyway.
      expect(cubit.state.persons[1].linked, isTrue);
      expect(cubit.state.canRemovePerson(1), isFalse);
      // A linked payee locks the PAYER's own trash too: deleting the payer a
      // payee has authorized would strand that commitment.
      expect(cubit.state.canRemovePerson(0), isFalse);
      cubit.removePerson(1);
      expect(cubit.state.persons.length, 2);
      await cubit.close();
    });

    test('an empty cart cannot advance, and "It\'s just me" reaches plans',
        () async {
      final cubit = await atRoster();
      cubit.setPersonTraining(0, false);

      // A payer who is not training with nobody else on the roster would send
      // `memberships: []` and take a 400.
      expect(cubit.state.anyoneTraining, isFalse);
      cubit.continueToPlans();
      expect(cubit.state.step, KioskSignupStep.people);

      cubit.setPersonTraining(0, true);
      expect(cubit.state.anyoneTraining, isTrue);
      cubit.continueToPlans();
      expect(cubit.state.step, KioskSignupStep.plans);
      expect(cubit.state.isGroup, isFalse);
      await cubit.close();
    });
  });

  group('the existing-member search', () {
    test('it debounces, and a stale response can never overwrite a newer one',
        () async {
      final first = Completer<CrmMembersListResponse>();
      final second = Completer<CrmMembersListResponse>();
      var call = 0;
      when(() => membersList.getMembersList(any())).thenAnswer((_) {
        call++;
        return call == 1 ? first.future : second.future;
      });

      final cubit = await atRoster();
      cubit.openMatchSearch();
      // Three keystrokes inside one debounce window are ONE fetch.
      cubit.searchExistingPeople('el');
      cubit.searchExistingPeople('ell');
      await _tick();
      expect(call, 1);

      cubit.searchExistingPeople('ella');
      await _tick();
      expect(call, 2);

      // The NEWER query answers first.
      second.complete(_page([_row('mem-ella', 'Ella Bell')]));
      await _settle();
      expect(cubit.state.matches.single.name, 'Ella Bell');

      // The older one lands late and is DISCARDED — otherwise a slow reply for
      // "ell" would overwrite the results the member is already looking at.
      first.complete(_page([_row('mem-old', 'Elliot Stone')]));
      await _settle();
      expect(cubit.state.matches.single.name, 'Ella Bell');
      expect(cubit.state.matchSearching, isFalse);
      await cubit.close();
    });

    test('picking a row lands on the same confirm card the 409 route does',
        () async {
      final cubit = await atRoster();
      cubit.openMatchSearch();
      expect(cubit.state.step, KioskSignupStep.match);
      cubit.pickMatchRow(_row('mem-ella', 'Ella Bell'));

      expect(cubit.state.matchSearchOpen, isFalse);
      expect(cubit.state.matchCandidate?.memberId, 'mem-ella');
      expect(cubit.state.matchCandidate?.firstName, 'Ella');
      expect(cubit.state.matchCandidate?.lastName, 'Bell');

      cubit.confirmMatch();
      expect(cubit.state.persons[1].memberId, 'mem-ella');
      expect(cubit.state.persons[1].wasExisting, isTrue);
      await cubit.close();
    });
  });

  group('per-person waivers', () {
    test('two people on the SAME plan each sign its waiver', () async {
      final cubit = await atRoster();
      await addElla(cubit);
      cubit.continueToPlans();
      // Both on the kids plan, which carries one waiver.
      cubit.selectPlan(kidsPlan);
      cubit.continueFromPlans();
      cubit.selectPlan(kidsPlan);
      cubit.continueFromPlans();
      await _settle();
      await cubit.signPayerAuth(signerName: 'Marcus Bell');
      await _settle();
      await cubit.signWaiver(signerName: 'Marcus Bell');
      await _settle();
      expect(cubit.state.step, KioskSignupStep.waivers);
      await cubit.signWaiver(signerName: 'Marcus Bell');

      // Keyed on the MEMBER: keying on the waiver id alone would silently skip
      // the second person and hand the backend an unsigned member.
      final signed = verify(
        () => memberships.recordWaiverSignature(
          waiverId: waiverId,
          gymId: gymId,
          memberId: captureAny(named: 'memberId'),
          waiverVersionId: any(named: 'waiverVersionId'),
          signerName: any(named: 'signerName'),
        ),
      ).captured.cast<String>();
      expect(signed, ['mem-2', 'mem-1']);
      expect(cubit.state.step, KioskSignupStep.card);
      await cubit.close();
    });

    test('a republished payer-auth agreement (409) reloads instead of linking',
        () async {
      final cubit = await atRoster();
      await addElla(cubit);
      cubit.continueToPlans();
      cubit.selectPlan(soloPlan);
      cubit.continueFromPlans();
      cubit.selectPlan(kidsPlan);
      cubit.continueFromPlans();
      await _settle();

      when(
        () => member.linkMemberAccount(
          any(),
          payerMemberId: any(named: 'payerMemberId'),
          waiverVersionId: any(named: 'waiverVersionId'),
          signerName: any(named: 'signerName'),
          consentAcknowledged: any(named: 'consentAcknowledged'),
        ),
      ).thenThrow(const ServerException('stale', statusCode: 409));
      await cubit.signPayerAuth(signerName: 'Marcus Bell');
      await _settle();

      expect(cubit.state.payerAuthStale, isTrue);
      expect(cubit.state.payerAuthPending, isTrue);
      expect(cubit.state.persons[1].linked, isFalse);
      // The body is re-read so nothing is signed against text nobody saw.
      verify(() => member.getAuthorizedPayerWaiver('mem-2')).called(2);
      await cubit.close();
    });
  });

  group('"Skip" on the plan step (the founder\'s skip)', () {
    test('it is GROUP-only — a solo signup cannot empty its own cart',
        () async {
      final cubit = await atRoster();
      cubit.continueToPlans();
      expect(cubit.state.isGroup, isFalse);

      // The control is not offered on a solo signup, and the cubit refuses it
      // too: skipping the only person would send `memberships: []` and take a
      // 400, and at least one person must get a membership.
      cubit.skipPlanForPerson();
      expect(cubit.state.step, KioskSignupStep.plans);
      expect(cubit.state.payer.training, isTrue);
      expect(cubit.state.anyoneTraining, isTrue);
      await cubit.close();
    });

    test('skipping one person drops them from the CART and moves to the next',
        () async {
      final cubit = await atRoster();
      await addElla(cubit);
      cubit.continueToPlans();
      expect(cubit.state.activePersonIndex, 0);

      // The payer changes their mind: no membership for them, on to the child.
      cubit.skipPlanForPerson();
      expect(cubit.state.step, KioskSignupStep.plans);
      expect(cubit.state.activePersonIndex, 1);
      // It reuses `training` rather than a parallel "skipped" concept, so the
      // cart, the waiver queue and the review all follow for free.
      expect(cubit.state.persons[0].training, isFalse);
      expect(cubit.state.persons[0].selectedPlanId, isNull);
      expect(cubit.state.trainingPersonIndexes, [1]);

      cubit.selectPlan(kidsPlan);
      cubit.continueFromPlans();
      await _settle();
      // Only the child is in the cart, and the parent is `payer_member_id`.
      await cubit.signPayerAuth(signerName: 'Marcus Bell');
      await _settle();
      await cubit.signWaiver(signerName: 'Marcus Bell');
      expect(cubit.state.step, KioskSignupStep.card);
      cubit.submitCard(paymentMethodId: 'pm_1');
      await _settle();

      final request = verify(() => member.previewStartMemberships(captureAny()))
          .captured
          .single as MemberMembershipsStartRequest;
      expect(request.payerMemberId, 'mem-1');
      expect(request.memberships.single.memberId, 'mem-2');
      await cubit.close();
    });

    test('skipping the LAST person left goes straight into the waiver run',
        () async {
      final cubit = await atRoster();
      await addElla(cubit);
      cubit.continueToPlans();
      cubit.selectPlan(soloPlan);
      cubit.continueFromPlans();
      expect(cubit.state.activePersonIndex, 1);

      // The child is skipped; the parent already picked, so there is nothing
      // left to choose and the run begins.
      cubit.skipPlanForPerson();
      await _settle();
      expect(cubit.state.step, KioskSignupStep.waivers);
      expect(cubit.state.trainingPersonIndexes, [0]);
      await cubit.close();
    });

    test('skipping EVERYBODY returns to the People step, never an empty cart',
        () async {
      final cubit = await atRoster();
      await addElla(cubit);
      cubit.continueToPlans();

      cubit.skipPlanForPerson();
      expect(cubit.state.activePersonIndex, 1);
      cubit.skipPlanForPerson();

      // **The founder's own resolution.** The roster is where a person can be
      // ticked back on or taken off, and it already refuses to leave with an
      // empty cart and says why — so the backend's empty-cart 400 stays
      // unreachable by construction.
      expect(cubit.state.step, KioskSignupStep.people);
      expect(cubit.state.anyoneTraining, isFalse);
      // And Continue out of the roster is blocked while it holds.
      cubit.continueToPlans();
      expect(cubit.state.step, KioskSignupStep.people);
      // Ticking anybody back on releases it immediately.
      cubit.setPersonTraining(1, true);
      cubit.continueToPlans();
      expect(cubit.state.step, KioskSignupStep.plans);
      expect(cubit.state.activePersonIndex, 1);
      await cubit.close();
    });
  });
}

/// Let the cubit's `unawaited` reads settle.
Future<void> _settle() => Future<void>.delayed(Duration.zero);

/// Past the search debounce.
Future<void> _tick() => Future<void>.delayed(
      kKioskSearchDebounce + const Duration(milliseconds: 50),
    );

AllViewRow _row(String id, String name) => AllViewRow(
      memberId: id,
      name: name,
      email: 'someone@example.com',
      membershipStatus: MembershipStatus.active,
      membershipText: 'Monthly',
    );

CrmMembersListResponse _page(List<MemberRow> rows) => CrmMembersListResponse(
      view: MembersListView.all,
      filters: const MembersListFilters(),
      data: rows,
    );

AuthorizedPayerWaiver _payerAuthWaiver() => const AuthorizedPayerWaiver(
      waiverId: 'payer-waiver-1',
      versionId: 'payer-ver-1',
      name: 'Authorized Payer Agreement',
      body: 'I authorise myself to pay for {{payee_name}}.',
    );

MembershipPlanResponse _recurringPlan() => MembershipPlanResponse(
      planId: 'plan-1',
      gymId: 'gym-1',
      planName: 'Unlimited',
      imageUrl: 'https://cdn/plan-1.png',
      planType: PlanType.recurring,
      durationAmount: 1,
      isPublic: true,
      createdAt: DateTime.utc(2026),
      waiverIds: const ['waiver-1'],
      activePrice: MembershipPlanPriceResponse(
        priceId: 'price-1',
        planId: 'plan-1',
        gymId: 'gym-1',
        stripePriceId: 'price_stripe_1',
        price: 14900,
        isActive: true,
        createdAt: DateTime.utc(2026),
      ),
    );

MembershipPlanResponse _kidsPlan() => MembershipPlanResponse(
      planId: 'plan-2',
      gymId: 'gym-1',
      planName: 'Kids Program',
      imageUrl: 'https://cdn/plan-2.png',
      planType: PlanType.recurring,
      durationAmount: 1,
      isPublic: true,
      createdAt: DateTime.utc(2026),
      waiverIds: const ['waiver-1'],
      activePrice: MembershipPlanPriceResponse(
        priceId: 'price-2',
        planId: 'plan-2',
        gymId: 'gym-1',
        stripePriceId: 'price_stripe_2',
        price: 8900,
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
          description: 'Membership',
          stripePriceId: 'price_stripe_1',
        ),
      ],
    );

MemberMembershipsStartPreview _preview() => MemberMembershipsStartPreview(
      dueNow: _invoice(23800),
      recurring: _invoice(23800),
    );

/// The start breakdown. [failedMemberId] fails exactly that member's item;
/// [unknownMemberId] gives that member the forward-compatible `unknown` status
/// (neither created NOR failed — the shape a `[created, unknown]` partial
/// takes); [only] narrows the results to one member (what a retry gets back).
MemberMembershipsStartResponse _startResponse({
  String? failedMemberId,
  String? unknownMemberId,
  String? only,
}) {
  final ids = only == null ? const ['mem-1', 'mem-2'] : [only];
  MemberMembershipsStartStatus statusOf(String id) {
    if (id == failedMemberId) return MemberMembershipsStartStatus.failed;
    if (id == unknownMemberId) return MemberMembershipsStartStatus.unknown;
    return MemberMembershipsStartStatus.created;
  }

  return MemberMembershipsStartResponse(
    chargeCount: 1,
    multipleCharges: false,
    results: [
      for (final id in ids)
        MemberMembershipsStartResultItem(
          memberId: id,
          planId: id == 'mem-1' ? 'plan-1' : 'plan-2',
          planType: PlanType.recurring,
          status: statusOf(id),
          itemId: statusOf(id) == MemberMembershipsStartStatus.created
              ? 'item-$id'
              : null,
          error: statusOf(id) == MemberMembershipsStartStatus.failed
              ? 'card_declined'
              : null,
        ),
    ],
  );
}
