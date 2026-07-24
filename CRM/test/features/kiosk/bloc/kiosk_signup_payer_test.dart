import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:crm/core/errors/exceptions.dart';
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
import 'package:crm/features/member_details/data/models/member_payment_method_status.dart';
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

/// **The payer gate — the kiosk never charges a pre-existing card.**
///
/// An EXISTING member may be this signup's payer only while they have no
/// payment method attached at all; they then still type a fresh card, which
/// becomes the first one that account has ever had. Get the gate wrong and a
/// recurring cart's `set_default: true` puts a stranger's card on someone's
/// profile, and the next front-desk "charge the card on file" bills the wrong
/// person.
///
/// Every test here is that one sentence from a different angle, and the
/// fail-closed ones are the load-bearing pair: a check that ERRORS must read
/// as "not eligible", never as "no card on file".
void main() {
  const gymId = 'gym-1';
  const planId = 'plan-1';
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
        .thenAnswer((_) async => [_plan()]);
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
    // The default is the eligible answer; each test that cares overrides it.
    when(() => member.getPaymentMethodStatus(any())).thenAnswer(
      (_) async => const MemberPaymentMethodStatus(hasPaymentMethod: false),
    );
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

  /// Type the payer's own details and press Continue — the create call.
  Future<KioskSignupCubit> submitPayer(KioskSignupCubit cubit) async {
    cubit.submitDetails(
      firstName: 'Marcus',
      lastName: 'Bell',
      email: 'marcus.bell@gmail.com',
    );
    await cubit.submitExtraDetails();
    return cubit;
  }

  /// The payer's create 409s against an account that already exists.
  void payerIsADuplicate() {
    when(() => member.createMember(any())).thenThrow(
      const DuplicateMemberException([
        DuplicateMemberMatch(
          memberId: 'mem-marcus-existing',
          firstName: 'Marcus',
          lastName: 'Bell',
          email: 'marcus.bell@gmail.com',
        ),
      ]),
    );
  }

  group('entry A — "is this you?" on a payer duplicate', () {
    test('an ELIGIBLE match is offered as a confirm card, not a stop',
        () async {
      final cubit = build();
      payerIsADuplicate();
      await submitPayer(cubit);

      expect(cubit.state.step, KioskSignupStep.payerMatch);
      expect(cubit.state.stopReason, isNull);
      expect(cubit.state.matchCandidate?.memberId, 'mem-marcus-existing');
      verify(() => member.getPaymentMethodStatus('mem-marcus-existing'))
          .called(1);
      await cubit.close();
    });

    test('"Yes, that\'s me" adopts the id and NEVER creates a member',
        () async {
      final cubit = build();
      payerIsADuplicate();
      await submitPayer(cubit);
      cubit.confirmPayerMatch();

      expect(cubit.state.step, KioskSignupStep.people);
      expect(cubit.state.payer.memberId, 'mem-marcus-existing');
      expect(cubit.state.payer.wasExisting, isTrue);
      expect(cubit.state.payer.isPayer, isTrue);
      // The ONE create is the attempt that 409'd. Adoption writes nothing.
      verify(() => member.createMember(any())).called(1);
      verifyNever(() => member.updateMember(any(), any()));
      // Nothing behind the roster for them: there is no typed record of
      // theirs to go back to, and no route that could PUT over the gym's.
      cubit.back();
      expect(cubit.state.step, KioskSignupStep.people);
      await cubit.close();
    });

    test('"No" is the terminal front-desk stop', () async {
      final cubit = build();
      payerIsADuplicate();
      await submitPayer(cubit);
      cubit.declinePayerMatch();

      expect(cubit.state.step, KioskSignupStep.stop);
      expect(cubit.state.stopReason, KioskSignupStopReason.duplicateMember);
      await cubit.close();
    });

    test('a match with a card ON FILE is never offered — terminal stop',
        () async {
      when(() => member.getPaymentMethodStatus(any())).thenAnswer(
        (_) async => const MemberPaymentMethodStatus(hasPaymentMethod: true),
      );
      final cubit = build();
      payerIsADuplicate();
      await submitPayer(cubit);

      expect(cubit.state.step, KioskSignupStep.stop);
      expect(cubit.state.stopReason, KioskSignupStopReason.duplicateMember);
      // The match is never rendered when it cannot be acted on.
      expect(cubit.state.matchCandidate, isNull);
      await cubit.close();
    });

    test('FAIL CLOSED — a check that ERRORS is treated as not eligible',
        () async {
      when(() => member.getPaymentMethodStatus(any()))
          .thenThrow(const ServerException('boom', statusCode: 500));
      final cubit = build();
      payerIsADuplicate();
      await submitPayer(cubit);

      // A failure must NEVER read as "no card on file".
      expect(cubit.state.step, KioskSignupStep.stop);
      expect(cubit.state.stopReason, KioskSignupStopReason.duplicateMember);
      expect(cubit.state.matchCandidate, isNull);
      await cubit.close();
    });

    test('FAIL CLOSED — a 404 on the check is treated as not eligible',
        () async {
      when(() => member.getPaymentMethodStatus(any()))
          .thenThrow(const ServerException('nope', statusCode: 404));
      final cubit = build();
      payerIsADuplicate();
      await submitPayer(cubit);

      expect(cubit.state.step, KioskSignupStep.stop);
      expect(cubit.state.stopReason, KioskSignupStopReason.duplicateMember);
      await cubit.close();
    });
  });

  group('entry B — the payer picker', () {
    /// The payer created, standing on the roster, picker open.
    Future<KioskSignupCubit> atPicker() async {
      final cubit = await submitPayer(build());
      expect(cubit.state.step, KioskSignupStep.people);
      expect(cubit.state.canSwitchPayer, isTrue);
      cubit.openPayerPick();
      expect(cubit.state.step, KioskSignupStep.payerPick);
      return cubit;
    }

    test('an ELIGIBLE pick becomes the payer; the signer stays a payee',
        () async {
      final cubit = await atPicker();
      await cubit.pickPayerRow(_row('mem-dad', 'Rick Bell'));

      expect(cubit.state.step, KioskSignupStep.people);
      expect(cubit.state.persons, hasLength(2));
      // Only the PAYER role moved.
      expect(cubit.state.payer.memberId, 'mem-dad');
      expect(cubit.state.payer.wasExisting, isTrue);
      expect(cubit.state.payer.isPayer, isTrue);
      // The membership check defaults ON for everybody, adopted included —
      // they can untick it on the roster if they are only paying.
      expect(cubit.state.payer.training, isTrue);
      expect(cubit.state.persons[1].memberId, 'mem-1');
      expect(cubit.state.persons[1].firstName, 'Marcus');
      expect(cubit.state.persons[1].isPayer, isFalse);
      expect(cubit.state.persons[1].training, isTrue);
      // The adopted payer is never created.
      verify(() => member.createMember(any())).called(1);
      await cubit.close();
    });

    test('nothing can be charged until the new payer authorizes every payee',
        () async {
      final cubit = await atPicker();
      await cubit.pickPayerRow(_row('mem-dad', 'Rick Bell'));

      // The person who started the signup is a payee now, so the
      // link-before-start invariant covers them.
      expect(cubit.state.everyPayeeLinked, isFalse);

      cubit.continueToPlans();
      cubit.selectPlan(planId);
      cubit.continueFromPlans();
      cubit.selectPlan(planId);
      cubit.continueFromPlans();
      await _settle();
      // The run opens on the payer-auth agreement for the demoted signer.
      expect(cubit.state.payerAuthPending, isTrue);
      verifyNever(() => member.previewStartMemberships(any()));

      await cubit.signPayerAuth(signerName: 'Rick Bell');
      await _settle();
      verify(
        () => member.linkMemberAccount(
          'mem-1',
          payerMemberId: 'mem-dad',
          waiverVersionId: any(named: 'waiverVersionId'),
          signerName: 'Rick Bell',
          consentAcknowledged: true,
        ),
      ).called(1);
      expect(cubit.state.everyPayeeLinked, isTrue);

      await cubit.signWaiver(signerName: 'Rick Bell');
      await _settle();
      await cubit.signWaiver(signerName: 'Rick Bell');
      expect(cubit.state.step, KioskSignupStep.card);
      cubit.submitCard(paymentMethodId: 'pm_1', brand: 'visa', last4: '4242');
      await _settle();
      await cubit.pay();

      final request = verify(
        () => member.startMemberships(
          captureAny(),
          receiveTimeout: any(named: 'receiveTimeout'),
        ),
      ).captured.single as MemberMembershipsStartRequest;
      expect(request.payerMemberId, 'mem-dad');
      expect(
        request.memberships.map((m) => m.memberId),
        containsAll(<String>['mem-dad', 'mem-1']),
      );
      expect(cubit.state.step, KioskSignupStep.welcome);
      await cubit.close();
    });

    test('a card ON FILE is refused INLINE — the flow carries on', () async {
      when(() => member.getPaymentMethodStatus(any())).thenAnswer(
        (_) async => const MemberPaymentMethodStatus(hasPaymentMethod: true),
      );
      final cubit = await atPicker();
      await cubit.pickPayerRow(_row('mem-dad', 'Rick Bell'));

      expect(cubit.state.payerRefusal, KioskPayerEligibility.hasPaymentMethod);
      // Not a stop, and the payer seat is untouched.
      expect(cubit.state.step, KioskSignupStep.payerPick);
      expect(cubit.state.stopReason, isNull);
      expect(cubit.state.payer.memberId, 'mem-1');
      expect(cubit.state.persons, hasLength(1));

      // They can simply carry on paying themselves.
      cubit.back();
      expect(cubit.state.step, KioskSignupStep.people);
      expect(cubit.state.payerRefusal, isNull);
      verifyNever(() => member.previewStartMemberships(any()));
      await cubit.close();
    });

    test('FAIL CLOSED — a check that ERRORS refuses inline, never adopts',
        () async {
      when(() => member.getPaymentMethodStatus(any()))
          .thenThrow(const ServerException('boom', statusCode: 500));
      final cubit = await atPicker();
      await cubit.pickPayerRow(_row('mem-dad', 'Rick Bell'));

      // A failure must NEVER read as "no card on file".
      expect(cubit.state.payerRefusal, KioskPayerEligibility.unknown);
      expect(cubit.state.payer.memberId, 'mem-1');
      expect(cubit.state.payer.wasExisting, isFalse);
      expect(cubit.state.persons, hasLength(1));
      expect(cubit.state.step, KioskSignupStep.payerPick);
      await cubit.close();
    });

    test('a CRM hit already on the roster REDIRECTS to the list, no check',
        () async {
      final cubit = await submitPayer(build());
      await cubit.addPerson(
        firstName: 'Ella',
        lastName: 'Bell',
        email: 'ella.bell@gmail.com',
      );
      cubit.skipPersonDetails();
      cubit.openPayerPick();
      await cubit.pickPayerRow(_row('mem-2', 'Ella Bell'));

      // A redirect, not a rejection: they are pickable from the roster list.
      expect(cubit.state.payerRefusal, KioskPayerEligibility.alreadyInSignup);
      // And crucially NOT inserted a second time.
      expect(cubit.state.persons, hasLength(2));
      verifyNever(() => member.getPaymentMethodStatus(any()));
      await cubit.close();
    });

    test('the CURRENT payer is not selectable, from either list', () async {
      final cubit = await submitPayer(build());
      cubit.openPayerPick();

      // Not offered by the roster list...
      expect(cubit.state.payerCandidateIndexes, isEmpty);
      // ...and picking them anyway is a no-op that never reaches the gate.
      await cubit.pickPayerFromRoster(0);
      await cubit.pickPayerRow(_row('mem-1', 'Marcus Bell'));
      expect(cubit.state.payer.memberId, 'mem-1');
      expect(cubit.state.payerRefusal, isNull);
      verifyNever(() => member.getPaymentMethodStatus(any()));
      await cubit.close();
    });

    test('the offer is withdrawn once anything has committed', () async {
      final cubit = await submitPayer(build());
      await cubit.addPerson(
        firstName: 'Ella',
        lastName: 'Bell',
        email: 'ella.bell@gmail.com',
      );
      cubit.skipPersonDetails();
      cubit.continueToPlans();
      cubit.selectPlan(planId);
      cubit.continueFromPlans();
      cubit.selectPlan(planId);
      cubit.continueFromPlans();
      await _settle();
      await cubit.signPayerAuth(signerName: 'Marcus Bell');
      await _settle();

      // A payee is linked to THIS payer now, and there is no unlink call.
      expect(cubit.state.canSwitchPayer, isFalse);
      cubit.openPayerPick();
      expect(cubit.state.step, isNot(KioskSignupStep.payerPick));
      await cubit.close();
    });

    test('a SECOND swap is refused — the first adopted payer is not strandable',
        () async {
      final cubit = await submitPayer(build());
      cubit.openPayerPick();
      await cubit.pickPayerRow(_row('mem-dad', 'Rick Bell'));

      expect(cubit.state.canSwitchPayer, isFalse);
      cubit.openPayerPick();
      expect(cubit.state.step, KioskSignupStep.people);
      await cubit.close();
    });
  });

  group('entry B — picking somebody already on the roster', () {
    /// The payer, plus Ella, with the picker open.
    Future<KioskSignupCubit> atPickerWithElla() async {
      final cubit = await submitPayer(build());
      await cubit.addPerson(
        firstName: 'Ella',
        lastName: 'Bell',
        email: 'ella.bell@gmail.com',
      );
      cubit.skipPersonDetails();
      cubit.openPayerPick();
      expect(cubit.state.payerCandidateIndexes, [1]);
      return cubit;
    }

    test('a roster pick promotes them and demotes the previous payer',
        () async {
      final cubit = await atPickerWithElla();
      await cubit.pickPayerFromRoster(1);

      expect(cubit.state.step, KioskSignupStep.people);
      expect(cubit.state.persons, hasLength(2));
      // A straight swap: promoted to the head, the old payer takes their seat.
      expect(cubit.state.payer.memberId, 'mem-2');
      expect(cubit.state.payer.firstName, 'Ella');
      expect(cubit.state.payer.isPayer, isTrue);
      // Promotion moves the PAYER role and nothing else — they were getting a
      // membership before and they still are.
      expect(cubit.state.payer.training, isTrue);
      expect(cubit.state.persons[1].memberId, 'mem-1');
      expect(cubit.state.persons[1].isPayer, isFalse);
      expect(cubit.state.persons[1].training, isTrue);
      // Nobody is created by a promotion.
      verify(() => member.createMember(any())).called(2);
      await cubit.close();
    });

    test('the gate runs for a ROSTER pick too — a card on file refuses',
        () async {
      final cubit = await atPickerWithElla();
      when(() => member.getPaymentMethodStatus(any())).thenAnswer(
        (_) async => const MemberPaymentMethodStatus(hasPaymentMethod: true),
      );
      await cubit.pickPayerFromRoster(1);

      // No shortcut for somebody this signup created: the check runs, and it
      // refuses exactly as a CRM pick would.
      verify(() => member.getPaymentMethodStatus('mem-2')).called(1);
      expect(cubit.state.payerRefusal, KioskPayerEligibility.hasPaymentMethod);
      expect(cubit.state.payer.memberId, 'mem-1');
      await cubit.close();
    });

    test('FAIL CLOSED — a failed check on a roster pick refuses', () async {
      final cubit = await atPickerWithElla();
      when(() => member.getPaymentMethodStatus(any()))
          .thenThrow(const ServerException('boom', statusCode: 500));
      await cubit.pickPayerFromRoster(1);

      expect(cubit.state.payerRefusal, KioskPayerEligibility.unknown);
      // The payer seat is untouched.
      expect(cubit.state.payer.memberId, 'mem-1');
      expect(cubit.state.persons[1].memberId, 'mem-2');
      await cubit.close();
    });

    test('a promoted payer still authorizes everyone before any charge',
        () async {
      final cubit = await atPickerWithElla();
      await cubit.pickPayerFromRoster(1);
      expect(cubit.state.everyPayeeLinked, isFalse);

      cubit.continueToPlans();
      cubit.selectPlan(planId);
      cubit.continueFromPlans();
      cubit.selectPlan(planId);
      cubit.continueFromPlans();
      await _settle();
      expect(cubit.state.payerAuthPending, isTrue);
      verifyNever(() => member.previewStartMemberships(any()));

      await cubit.signPayerAuth(signerName: 'Ella Bell');
      await _settle();
      verify(
        () => member.linkMemberAccount(
          'mem-1',
          payerMemberId: 'mem-2',
          waiverVersionId: any(named: 'waiverVersionId'),
          signerName: 'Ella Bell',
          consentAcknowledged: any(named: 'consentAcknowledged'),
        ),
      ).called(1);
      expect(cubit.state.everyPayeeLinked, isTrue);
      await cubit.close();
    });
  });

  group('the empty-cart guard', () {
    test('nothing advances, and no request is ever built, with none ticked',
        () async {
      final cubit = await submitPayer(build());
      cubit.setPersonTraining(0, false);
      expect(cubit.state.anyoneTraining, isFalse);

      cubit.continueToPlans();
      // Blocked, not skipped: there is no path past this that sends an empty
      // cart, and nothing downstream is touched.
      expect(cubit.state.step, KioskSignupStep.people);
      verifyNever(() => member.previewStartMemberships(any()));
      verifyNever(
        () => member.startMemberships(
          any(),
          receiveTimeout: any(named: 'receiveTimeout'),
        ),
      );

      // Ticking anybody releases it immediately.
      cubit.setPersonTraining(0, true);
      expect(cubit.state.anyoneTraining, isTrue);
      cubit.continueToPlans();
      expect(cubit.state.step, KioskSignupStep.plans);
      await cubit.close();
    });

    test('a MIXED roster charges only the people who are getting one',
        () async {
      final cubit = await submitPayer(build());
      await cubit.addPerson(
        firstName: 'Ella',
        lastName: 'Bell',
        email: 'ella.bell@gmail.com',
      );
      cubit.skipPersonDetails();
      // The payer registers only; the child gets the membership.
      cubit.setPersonTraining(0, false);
      expect(cubit.state.trainingPersonIndexes, [1]);

      cubit.continueToPlans();
      cubit.selectPlan(planId);
      cubit.continueFromPlans();
      await _settle();
      await cubit.signPayerAuth(signerName: 'Marcus Bell');
      await _settle();
      await cubit.signWaiver(signerName: 'Marcus Bell');
      expect(cubit.state.step, KioskSignupStep.card);
      cubit.submitCard(paymentMethodId: 'pm_1', brand: 'visa', last4: '4242');
      await _settle();
      await cubit.pay();

      final request = verify(
        () => member.startMemberships(
          captureAny(),
          receiveTimeout: any(named: 'receiveTimeout'),
        ),
      ).captured.single as MemberMembershipsStartRequest;
      // The unchecked payer is created and pays, but buys nothing.
      expect(request.payerMemberId, 'mem-1');
      expect(request.memberships.single.memberId, 'mem-2');
      await cubit.close();
    });
  });

  group('taking somebody off the roster asks first', () {
    Future<KioskSignupCubit> withElla() async {
      final cubit = await submitPayer(build());
      await cubit.addPerson(
        firstName: 'Ella',
        lastName: 'Bell',
        email: 'ella.bell@gmail.com',
      );
      cubit.skipPersonDetails();
      return cubit;
    }

    test('cancelling keeps them; confirming removes them', () async {
      final cubit = await withElla();
      cubit.askRemovePerson(1);
      expect(cubit.state.removeConfirmIndex, 1);

      cubit.dismissRemovePerson();
      expect(cubit.state.removeConfirmIndex, isNull);
      expect(cubit.state.persons, hasLength(2));

      cubit.askRemovePerson(1);
      cubit.confirmRemovePerson();
      expect(cubit.state.removeConfirmIndex, isNull);
      expect(cubit.state.persons, hasLength(1));
      await cubit.close();
    });

    test('it is not offered once that person is linked', () async {
      final cubit = await withElla();
      cubit.continueToPlans();
      cubit.selectPlan(planId);
      cubit.continueFromPlans();
      cubit.selectPlan(planId);
      cubit.continueFromPlans();
      await _settle();
      await cubit.signPayerAuth(signerName: 'Marcus Bell');
      await _settle();

      // There is no unlink call, so removal stops being free.
      expect(cubit.state.canRemovePerson(1), isFalse);
      cubit.askRemovePerson(1);
      expect(cubit.state.removeConfirmIndex, isNull);
      await cubit.close();
    });
  });

  group('an existing member owns their own record', () {
    test('a matched payee SKIPS the details step entirely', () async {
      final cubit = await submitPayer(build());
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
      cubit.confirmMatch();

      // Straight back to the roster: there is no blank-field pass, because
      // the kiosk can neither show nor overwrite their stored details.
      expect(cubit.state.step, KioskSignupStep.people);
      expect(cubit.state.persons[1].wasExisting, isTrue);
      // And Edit is refused for them even if something routed one in.
      cubit.editPersonDetails(1);
      expect(cubit.state.step, KioskSignupStep.people);
      verifyNever(() => member.updateMember(any(), any()));
      await cubit.close();
    });

    test('a NEW payee keeps the details step and round-trips an edit',
        () async {
      final cubit = await submitPayer(build());
      await cubit.addPerson(
        firstName: 'Ella',
        lastName: 'Bell',
        email: 'ella.bell@gmail.com',
      );
      expect(cubit.state.step, KioskSignupStep.personDetails);
      cubit.skipPersonDetails();
      expect(cubit.state.step, KioskSignupStep.people);

      cubit.editPersonDetails(1);
      expect(cubit.state.step, KioskSignupStep.personDetails);
      expect(cubit.state.activePersonIndex, 1);
      await cubit.submitPersonDetails(address: '4 Anvil Row');

      verify(() => member.updateMember('mem-2', any())).called(1);
      expect(cubit.state.step, KioskSignupStep.people);
      expect(cubit.state.persons[1].address, '4 Anvil Row');
      await cubit.close();
    });
  });

  group('deleting the payer always asks who pays next', () {
    /// Marcus (payer, mem-1) + Ella (payee, mem-2), on the roster.
    Future<KioskSignupCubit> withElla() async {
      final cubit = await submitPayer(build());
      await cubit.addPerson(
        firstName: 'Ella',
        lastName: 'Bell',
        email: 'ella.bell@gmail.com',
      );
      cubit.skipPersonDetails();
      return cubit;
    }

    test('the payer is removable, and removing them clears the payer and '
        'routes to the picker', () async {
      final cubit = await withElla();
      // The payer is removable now (group, nothing committed).
      expect(cubit.state.canRemovePerson(0), isTrue);

      cubit.askRemovePerson(0);
      expect(cubit.state.removeConfirmIndex, 0);
      cubit.confirmRemovePerson();

      // Nothing is auto-assigned: the signup has NO payer, and the flow is
      // parked on the picker to choose one.
      expect(cubit.state.step, KioskSignupStep.payerPick);
      expect(cubit.state.hasPayer, isFalse);
      expect(cubit.state.payerOrNull, isNull);
      expect(cubit.state.persons, hasLength(1));
      expect(cubit.state.persons.single.memberId, 'mem-2');
      expect(cubit.state.persons.single.isPayer, isFalse);
      // Every remaining person is now a candidate, index 0 included.
      expect(cubit.state.payerCandidateIndexes, [0]);
      await cubit.close();
    });

    test('Continue is blocked until a payer is chosen', () async {
      final cubit = await withElla();
      cubit.askRemovePerson(0);
      cubit.confirmRemovePerson();
      // Back out of the picker without choosing: the People step is reached
      // with no payer, and it cannot advance.
      cubit.back();
      expect(cubit.state.step, KioskSignupStep.people);
      expect(cubit.state.hasPayer, isFalse);

      cubit.continueToPlans();
      expect(cubit.state.step, KioskSignupStep.people);
      verifyNever(() => member.previewStartMemberships(any()));
      verifyNever(
        () => member.startMemberships(
          any(),
          receiveTimeout: any(named: 'receiveTimeout'),
        ),
      );
      await cubit.close();
    });

    test('a payer chosen after a delete still runs the fail-closed gate — a '
        'card on file refuses', () async {
      final cubit = await withElla();
      cubit.askRemovePerson(0);
      cubit.confirmRemovePerson();
      // Ella (the only one left) has a card on file now.
      when(() => member.getPaymentMethodStatus(any())).thenAnswer(
        (_) async => const MemberPaymentMethodStatus(hasPaymentMethod: true),
      );
      await cubit.pickPayerFromRoster(0);

      // The gate ran, and refused inline — no shortcut for the no-payer path.
      verify(() => member.getPaymentMethodStatus('mem-2')).called(1);
      expect(cubit.state.payerRefusal, KioskPayerEligibility.hasPaymentMethod);
      expect(cubit.state.hasPayer, isFalse);
      await cubit.close();
    });

    test('a payer chosen after a delete still runs the fail-closed gate — a '
        'failed check refuses', () async {
      final cubit = await withElla();
      cubit.askRemovePerson(0);
      cubit.confirmRemovePerson();
      when(() => member.getPaymentMethodStatus(any()))
          .thenThrow(const ServerException('boom', statusCode: 500));
      await cubit.pickPayerFromRoster(0);

      // A failure NEVER reads as "no card on file".
      expect(cubit.state.payerRefusal, KioskPayerEligibility.unknown);
      expect(cubit.state.hasPayer, isFalse);
      await cubit.close();
    });

    test('an ELIGIBLE pick after a delete seats them and re-enables Continue',
        () async {
      final cubit = await withElla();
      cubit.askRemovePerson(0);
      cubit.confirmRemovePerson();
      await cubit.pickPayerFromRoster(0);

      // Ella is the payer now, at the head, and the flow can advance again.
      expect(cubit.state.hasPayer, isTrue);
      expect(cubit.state.payer.memberId, 'mem-2');
      expect(cubit.state.payer.isPayer, isTrue);
      expect(cubit.state.step, KioskSignupStep.people);
      cubit.continueToPlans();
      expect(cubit.state.step, KioskSignupStep.plans);
      await cubit.close();
    });

    test('a solo payer is NOT removable — deleting the only person is not a '
        'thing', () async {
      final cubit = await submitPayer(build());
      expect(cubit.state.isGroup, isFalse);
      expect(cubit.state.canRemovePerson(0), isFalse);
      await cubit.close();
    });
  });
}

/// Let the cubit's `unawaited` reads settle.
Future<void> _settle() => Future<void>.delayed(Duration.zero);

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

MembershipPlanResponse _plan() => MembershipPlanResponse(
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

MemberMembershipsStartPreview _preview() => MemberMembershipsStartPreview(
      dueNow: PreviewInvoice(
        amountDue: 14900,
        subtotal: 14900,
        total: 14900,
        currency: 'usd',
        lines: const [
          PreviewInvoiceLine(
            amount: 14900,
            discountedAmount: 14900,
            description: 'Membership',
            stripePriceId: 'price_stripe_1',
          ),
        ],
      ),
      recurring: PreviewInvoice(
        amountDue: 14900,
        subtotal: 14900,
        total: 14900,
        currency: 'usd',
        lines: const [
          PreviewInvoiceLine(
            amount: 14900,
            discountedAmount: 14900,
            description: 'Membership',
            stripePriceId: 'price_stripe_1',
          ),
        ],
      ),
    );

MemberMembershipsStartResponse _startResponse() =>
    const MemberMembershipsStartResponse(
      chargeCount: 1,
      multipleCharges: false,
      results: [
        MemberMembershipsStartResultItem(
          memberId: 'mem-1',
          planId: 'plan-1',
          planType: PlanType.recurring,
          status: MemberMembershipsStartStatus.created,
          itemId: 'item-1',
        ),
      ],
    );
