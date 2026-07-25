import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:crm/features/kiosk/bloc/kiosk_session_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_state.dart';
import 'package:crm/features/member_details/data/models/authorized_payer_waiver.dart';
import 'package:crm/features/member_details/data/models/duplicate_member_match.dart';
import 'package:crm/features/member_details/data/models/member_detail_response.dart';
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
import 'package:crm/features/member_details/data/models/personal_info.dart';
import 'package:crm/features/member_details/data/models/plan_type.dart';
import 'package:crm/features/member_details/data/models/retention.dart';
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

/// **Who pays, and how they get into the lane.**
///
/// The kiosk is self-serve for existing members as well as new ones, so there
/// are three ways a payer is seated: the ordinary create, the "is this you?"
/// confirm on a duplicate 409, and the identify search where the member names
/// themselves. All three end at the SAME confirm-or-seat shape, and none of
/// them may quietly insert a second row for one member.
///
/// **There is no card check on any of them, deliberately.** An existing member
/// with a card on file is a perfectly good kiosk payer: they still type a
/// fresh card, and it replaces the one on their profile. What the kiosk never
/// does is CHARGE a card it did not just take — that half of the fresh-card law
/// is structural and lives in `kiosk_forbidden_imports_test.dart`.
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
    // The plan step reads an adopted member's history to decide whether a
    // trial is still on offer; nobody here has had one.
    when(() => member.getMemberDetail(any()))
        .thenAnswer((_) async => _detail());
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
    cubit.startAsNewMember();
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

  group('the first fork — new here, or already a member', () {
    test('the lane opens on the fork, and each side goes where it says',
        () async {
      final cubit = build();
      expect(cubit.state.step, KioskSignupStep.entry);

      cubit.startAsNewMember();
      expect(cubit.state.step, KioskSignupStep.details);
      // Back off either branch lands on the fork — nothing was typed on the
      // way in, so it is a safe destination.
      cubit.back();
      expect(cubit.state.step, KioskSignupStep.entry);

      cubit.startAsExistingMember();
      expect(cubit.state.step, KioskSignupStep.identify);
      cubit.back();
      expect(cubit.state.step, KioskSignupStep.entry);
      // Nothing has been written by either detour.
      verifyNever(() => member.createMember(any()));
      await cubit.close();
    });
  });

  group('entry A — the identify search', () {
    /// The existing member on the identify step, having typed a name.
    Future<KioskSignupCubit> atIdentify() async {
      final cubit = build();
      cubit.startAsExistingMember();
      cubit.searchExistingPeople('marc');
      return cubit;
    }

    test('tapping a row CONFIRMS first — nobody is seated by the tap',
        () async {
      final cubit = await atIdentify();
      await cubit.pickPayerRow(_row('mem-marcus-existing', 'Marcus Bell'));

      // Two members can share a name; a mis-tap on a shared iPad must not put
      // a stranger's account behind the card about to be typed.
      expect(cubit.state.step, KioskSignupStep.payerMatch);
      expect(cubit.state.payerMatchFromIdentify, isTrue);
      expect(cubit.state.matchCandidate?.memberId, 'mem-marcus-existing');
      expect(cubit.state.payer.memberId, isNull);
      // No roster row is inserted, and nothing is written.
      expect(cubit.state.persons, hasLength(1));
      verifyNever(() => member.createMember(any()));
      await cubit.close();
    });

    test('"Yes, that\'s me" adopts them and lands on the roster, no create',
        () async {
      final cubit = await atIdentify();
      await cubit.pickPayerRow(_row('mem-marcus-existing', 'Marcus Bell'));
      cubit.confirmPayerMatch();

      expect(cubit.state.step, KioskSignupStep.people);
      expect(cubit.state.payer.memberId, 'mem-marcus-existing');
      expect(cubit.state.payer.wasExisting, isTrue);
      expect(cubit.state.payer.isPayer, isTrue);
      expect(cubit.state.persons, hasLength(1));
      verifyNever(() => member.createMember(any()));
      verifyNever(() => member.updateMember(any(), any()));
      // No screen behind the roster for them: the kiosk never typed their
      // details and must never PUT its own guess over the gym's record.
      cubit.back();
      expect(cubit.state.step, KioskSignupStep.people);
      await cubit.close();
    });

    test('"No, that\'s not me" returns to the SEARCH, query intact', () async {
      final cubit = await atIdentify();
      await cubit.pickPayerRow(_row('mem-someone-else', 'Marcus Bellamy'));
      cubit.declinePayerMatch();

      // Nothing committed and they simply mis-tapped, so this is not the
      // terminal stop the duplicate route takes.
      expect(cubit.state.step, KioskSignupStep.identify);
      expect(cubit.state.stopReason, isNull);
      expect(cubit.state.matchCandidate, isNull);
      expect(cubit.state.payerMatchFromIdentify, isFalse);
      expect(cubit.state.matchQuery, 'marc');
      await cubit.close();
    });

    test('backing out of the search drops what a stranger typed', () async {
      final cubit = await atIdentify();
      cubit.back();

      expect(cubit.state.step, KioskSignupStep.entry);
      expect(cubit.state.matchQuery, isEmpty);
      expect(cubit.state.matches, isEmpty);
      await cubit.close();
    });
  });

  group('entry B — "is this you?" on a duplicate create', () {
    test('a duplicate is ALWAYS offered as a confirm card, never a stop',
        () async {
      final cubit = build();
      payerIsADuplicate();
      await submitPayer(cubit);

      // No card check stands between the 409 and the offer any more: whoever
      // is adopted types a fresh card, and it replaces theirs.
      expect(cubit.state.step, KioskSignupStep.payerMatch);
      expect(cubit.state.stopReason, isNull);
      expect(cubit.state.payerMatchFromIdentify, isFalse);
      expect(cubit.state.matchCandidate?.memberId, 'mem-marcus-existing');
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
      cubit.back();
      expect(cubit.state.step, KioskSignupStep.people);
      await cubit.close();
    });

    test('"No" on the DUPLICATE route is the terminal front-desk stop',
        () async {
      final cubit = build();
      payerIsADuplicate();
      await submitPayer(cubit);
      cubit.declinePayerMatch();

      // The create has already been refused, so there is nothing left the
      // kiosk can do with this name.
      expect(cubit.state.step, KioskSignupStep.stop);
      expect(cubit.state.stopReason, KioskSignupStopReason.duplicateMember);
      await cubit.close();
    });

    test('a 409 that names NOBODY is the terminal stop, and renders no match',
        () async {
      when(() => member.createMember(any()))
          .thenThrow(const DuplicateMemberException([]));
      final cubit = build();
      await submitPayer(cubit);

      expect(cubit.state.step, KioskSignupStep.stop);
      expect(cubit.state.stopReason, KioskSignupStopReason.duplicateMember);
      expect(cubit.state.matchCandidate, isNull);
      await cubit.close();
    });
  });

  group('entry C — the payer picker', () {
    /// The payer created, standing on the roster, picker open.
    Future<KioskSignupCubit> atPicker() async {
      final cubit = await submitPayer(build());
      expect(cubit.state.step, KioskSignupStep.people);
      expect(cubit.state.canSwitchPayer, isTrue);
      cubit.openPayerPick();
      expect(cubit.state.step, KioskSignupStep.payerPick);
      return cubit;
    }

    test('a pick becomes the payer; the signer stays a payee', () async {
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
      // Seated straight away: no card check gates the pick, and the adopted
      // payer is never created.
      expect(cubit.state.payerAlreadyInSignup, isFalse);
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
      expect(cubit.state.step, KioskSignupStep.results);
      await cubit.close();
    });

    test('a CRM hit already on the roster REDIRECTS to the list', () async {
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
      expect(cubit.state.payerAlreadyInSignup, isTrue);
      // And crucially NOT inserted a second time — two cart items for one
      // member is a double charge waiting to happen.
      expect(cubit.state.persons, hasLength(2));
      expect(cubit.state.payer.memberId, 'mem-1');
      await cubit.close();
    });

    test('the CURRENT payer is not selectable, from either list', () async {
      final cubit = await submitPayer(build());
      cubit.openPayerPick();

      // Not offered by the roster list...
      expect(cubit.state.payerCandidateIndexes, isEmpty);
      // ...and picking them anyway is a no-op.
      await cubit.pickPayerFromRoster(0);
      await cubit.pickPayerRow(_row('mem-1', 'Marcus Bell'));
      expect(cubit.state.payer.memberId, 'mem-1');
      expect(cubit.state.persons, hasLength(1));
      expect(cubit.state.payerAlreadyInSignup, isFalse);
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

    test('a SECOND swap is ALLOWED while nothing is linked or signed',
        () async {
      final cubit = await submitPayer(build());
      cubit.openPayerPick();
      await cubit.pickPayerRow(_row('mem-dad', 'Rick Bell'));

      // The first swap adopted an outsider (wasExisting). Changing who pays is
      // freely repeatable while nothing has committed, so the swap is still on
      // offer — the demoted former payer is just an unlinked roster payee, and
      // nobody is stranded.
      expect(cubit.state.payer.memberId, 'mem-dad');
      expect(cubit.state.payer.wasExisting, isTrue);
      expect(cubit.state.canSwitchPayer, isTrue);
      cubit.openPayerPick();
      expect(cubit.state.step, KioskSignupStep.payerPick);
      await cubit.close();
    });

    test('repeated roster swaps stay open until a payee is linked', () async {
      final cubit = await submitPayer(build()); // Marcus, mem-1
      await cubit.addPerson(
        firstName: 'Ella',
        lastName: 'Bell',
        email: 'ella.bell@gmail.com',
      );
      cubit.skipPersonDetails(); // Ella, mem-2, a payee

      // Swap 1: promote Ella to payer; Marcus becomes a payee.
      cubit.openPayerPick();
      await cubit.pickPayerFromRoster(1);
      expect(cubit.state.payer.memberId, 'mem-2');
      expect(cubit.state.canSwitchPayer, isTrue);

      // Swap 2: promote Marcus back. Still free — nothing is linked or signed.
      cubit.openPayerPick();
      await cubit.pickPayerFromRoster(1);
      expect(cubit.state.payer.memberId, 'mem-1');
      expect(cubit.state.canSwitchPayer, isTrue);

      // Authorize the payee — a link pins the payer, and ONLY then does the
      // swap offer close.
      cubit.continueToPlans();
      cubit.selectPlan(planId);
      cubit.continueFromPlans();
      cubit.selectPlan(planId);
      cubit.continueFromPlans();
      await _settle();
      await cubit.signPayerAuth(signerName: 'Marcus Bell');
      await _settle();

      expect(cubit.state.persons.any((p) => p.linked), isTrue);
      expect(cubit.state.canSwitchPayer, isFalse);
      cubit.openPayerPick();
      expect(cubit.state.step, isNot(KioskSignupStep.payerPick));
      await cubit.close();
    });
  });

  group('entry C — picking somebody already on the roster', () {
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

    test('a pick after a delete seats them and re-enables Continue', () async {
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

/// A member with no membership history at all — nobody in this file has had a
/// trial, so no trial is ever blocked here.
MemberDetailResponse _detail() => const MemberDetailResponse(
      memberId: 'mem-any',
      gymId: 'gym-1',
      firstName: 'Any',
      lastName: 'Member',
      membershipOverview: 'None',
      totalMonthlyRecurringPrice: 0,
      totalMembershipCount: 0,
      personalInfo: PersonalInfo(),
      retention: Retention(
        classStreakWeeks: 0,
        pointsBalance: 0,
        videosWatched: 0,
      ),
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
