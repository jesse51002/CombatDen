import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:crm/core/errors/exceptions.dart';
import 'package:crm/features/kiosk/bloc/kiosk_session_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_state.dart';
import 'package:crm/features/member_details/data/models/authorized_payer_waiver.dart';
import 'package:crm/features/member_details/data/models/duplicate_member_match.dart';
import 'package:crm/features/member_details/data/models/member_detail_response.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_request.dart';
import 'package:crm/features/member_details/data/models/members_management_create_request.dart';
import 'package:crm/features/member_details/data/models/members_management_response.dart';
import 'package:crm/features/member_details/data/models/members_management_update_request.dart';
import 'package:crm/features/member_details/data/models/membership_info.dart';
import 'package:crm/features/member_details/data/models/membership_plan_price_response.dart';
import 'package:crm/features/member_details/data/models/membership_plan_response.dart';
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
import 'package:crm/features/memberships/data/models/member_waiver_status.dart';
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

/// A waiver the gym already holds a compliant signature for is not asked for
/// again. The signal is `meets_floor` on
/// `GET /api/v1/waivers/signatures/by-member/{member_id}` — the SERVER's
/// verdict, the same rule the 422 purchase gate applies; the kiosk never
/// re-derives the floor.
///
/// The read FAILS CLOSED, the deliberate inverse of the two plan-block reads:
/// a needless signature costs the member twenty seconds, a MISSING one voids
/// the gym's legal protection. Only a positive `signed && meets_floor` takes a
/// waiver off the queue — a throw, a signature below the floor, and an absence
/// (the response is `required ∪ ever-signed` over their CURRENT memberships,
/// so a waiver on the plan they are about to BUY simply isn't in it) are all
/// asked for. The queue's LENGTH is what "waiver 1 of 2" counts.
void main() {
  const gymId = 'gym-1';
  const planId = 'plan-1';
  const waiverA = 'waiver-a';
  const waiverB = 'waiver-b';
  final t0 = DateTime.utc(2026, 1, 1, 18);

  late _MockMemberRepository member;
  late _MockMembershipsRepository memberships;
  late _MockMembersListRepository membersList;
  late _MockKioskSessionCubit session;

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

    when(() => memberships.listPlans(any()))
        .thenAnswer((_) async => [_plan()]);
    when(() => memberships.getWaiver(any(), any()))
        .thenAnswer((invocation) async =>
            _waiver(invocation.positionalArguments[0] as String));
    when(
      () => memberships.recordWaiverSignature(
        waiverId: any(named: 'waiverId'),
        gymId: any(named: 'gymId'),
        memberId: any(named: 'memberId'),
        waiverVersionId: any(named: 'waiverVersionId'),
        signerName: any(named: 'signerName'),
      ),
    ).thenAnswer((_) async => _MockSignatureResponse());
    // The fail-closed default: nothing known, so nothing is skipped. Each test
    // states its own history.
    when(() => memberships.listMemberWaiverStatus(any(), any()))
        .thenAnswer((_) async => const []);
    when(() => member.createMember(any())).thenAnswer((_) async => MemberCreateResult(
          memberId: 'mem-new',
          invite: InviteOutcome.queued,
        ));
    when(() => member.updateMember(any(), any()))
        .thenAnswer((_) async => _MockManagementResponse());
    when(() => member.getMemberDetail(any()))
        .thenAnswer((_) async => _detail());
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
        uuid: () => 'key-1',
      );

  /// An EXISTING member adopted through the identify search, walked from the
  /// plan grid into the waiver run of a plan carrying [waiverA] and [waiverB].
  Future<KioskSignupCubit> atWaiversAsExisting() async {
    final cubit = build();
    cubit.startAsExistingMember();
    await cubit.pickPayerRow(_row('mem-old', 'Marcus Bell'));
    cubit.confirmPayerMatch();
    cubit.continueToPlans();
    await _settle();
    cubit.selectPlan(planId);
    cubit.continueFromPlans();
    await _settle();
    return cubit;
  }

  group('a compliant prior signature is not asked for again', () {
    test('meets_floor drops it from the queue, and the COUNT follows',
        () async {
      when(() => memberships.listMemberWaiverStatus('mem-old', gymId))
          .thenAnswer((_) async => [
                _status(waiverA, signed: true, meetsFloor: true),
                _status(waiverB, signed: false),
              ]);
      final cubit = await atWaiversAsExisting();

      expect(cubit.state.step, KioskSignupStep.waivers);
      // Dropped, not stepped over — the subtitle counts real signatures.
      expect(cubit.state.waiverQueue, [waiverB]);
      expect(cubit.state.waiverIndex, 0);
      expect(cubit.state.currentWaiverId, waiverB);
      await cubit.close();
    });

    test('EVERY waiver already compliant skips the person entirely', () async {
      when(() => memberships.listMemberWaiverStatus('mem-old', gymId))
          .thenAnswer((_) async => [
                _status(waiverA, signed: true, meetsFloor: true),
                _status(waiverB, signed: true, meetsFloor: true),
              ]);
      final cubit = await atWaiversAsExisting();

      expect(cubit.state.step, KioskSignupStep.card);
      verifyNever(() => memberships.getWaiver(any(), any()));
      await cubit.close();
    });

    test('the read is fired ONCE per member, and Back then forward re-derives '
        'the SAME queue', () async {
      when(() => memberships.listMemberWaiverStatus('mem-old', gymId))
          .thenAnswer((_) async => [
                _status(waiverA, signed: true, meetsFloor: true),
                _status(waiverB, signed: false),
              ]);
      final cubit = await atWaiversAsExisting();

      expect(cubit.state.waiverQueue, [waiverB]);
      verify(() => memberships.listMemberWaiverStatus('mem-old', gymId))
          .called(1);

      cubit.back();
      expect(cubit.state.step, KioskSignupStep.plans);
      cubit.continueFromPlans();
      await _settle();
      expect(cubit.state.step, KioskSignupStep.waivers);
      expect(cubit.state.waiverQueue, [waiverB]);
      // The earlier `verify` consumed that call, so this covers a SECOND one.
      verifyNever(() => memberships.listMemberWaiverStatus(any(), any()));
      await cubit.close();
    });
  });

  group('everything that is not a positive verdict is ASKED', () {
    test('signed BELOW the floor is the re-sign case — asked', () async {
      when(() => memberships.listMemberWaiverStatus('mem-old', gymId))
          .thenAnswer((_) async => [
                // Signed at v1 while the floor has moved to v2.
                _status(waiverA, signed: true, meetsFloor: false),
                _status(waiverB, signed: true, meetsFloor: true),
              ]);
      final cubit = await atWaiversAsExisting();

      expect(cubit.state.waiverQueue, [waiverA]);
      expect(cubit.state.currentWaiverId, waiverA);
      await cubit.close();
    });

    test('a waiver ABSENT from the response is asked (fail closed)', () async {
      when(() => memberships.listMemberWaiverStatus('mem-old', gymId))
          .thenAnswer((_) async => [
                _status(waiverA, signed: true, meetsFloor: true),
              ]);
      final cubit = await atWaiversAsExisting();

      expect(cubit.state.waiverQueue, [waiverB]);
      await cubit.close();
    });

    test('an EMPTY response asks for everything', () async {
      when(() => memberships.listMemberWaiverStatus('mem-old', gymId))
          .thenAnswer((_) async => const []);
      final cubit = await atWaiversAsExisting();

      expect(cubit.state.waiverQueue, [waiverA, waiverB]);
      await cubit.close();
    });

    test('a THROWN read asks for everything (fail closed)', () async {
      when(() => memberships.listMemberWaiverStatus(any(), any()))
          .thenThrow(Exception('down'));
      final cubit = await atWaiversAsExisting();

      expect(cubit.state.waiverQueue, [waiverA, waiverB]);
      expect(cubit.state.currentWaiverId, waiverA);
      await cubit.close();
    });

    test('a 422 gate item is NEVER skipped, however compliant the read says '
        'it is', () async {
      // The gate is the backstop that makes a client-side skip safe at all, so
      // if the gate names it, the gate wins.
      when(() => memberships.listMemberWaiverStatus('mem-old', gymId))
          .thenAnswer((_) async => [
                _status(waiverA, signed: true, meetsFloor: true),
                _status(waiverB, signed: true, meetsFloor: true),
              ]);
      when(() => member.previewStartMemberships(any())).thenThrow(
        const WaiverGateException(
          message: 'unsigned waivers',
          unsigned: [
            WaiverGateItem(
              memberId: 'mem-old',
              waiverId: waiverA,
              name: 'Liability',
            ),
          ],
        ),
      );
      final cubit = await atWaiversAsExisting();
      // Everything was compliant, so the run went straight to the card.
      expect(cubit.state.step, KioskSignupStep.card);

      cubit.submitCard(paymentMethodId: 'pm_1', brand: 'visa', last4: '4242');
      await _settle();

      expect(cubit.state.step, KioskSignupStep.waivers);
      expect(cubit.state.waiverQueue, [waiverA]);
      expect(cubit.state.currentWaiverId, waiverA);
      await cubit.close();
    });
  });

  /// The two plans-step reads run CONCURRENTLY — one `Future.wait` per read
  /// over the roster, both fired from `continueToPlans` — and `Future.wait`
  /// propagates the FIRST error while cancelling nothing, so the hazard is one
  /// failure discarding answers that already landed. Each test asserts BOTH
  /// postures at once, because they are deliberate opposites: the plan gates
  /// fail OPEN, the waiver read fails CLOSED.
  group('the two reads are concurrent, and neither can move the other\'s '
      'posture', () {
    test('a roster\'s per-member reads are IN FLIGHT together, not one after '
        'another', () async {
      // Both gathers are held open on one gate so the PEAK in-flight count is
      // observable: 2 per read means both members' calls were open at once, 1
      // means they were awaited in turn.
      final gate = Completer<void>();
      var detailInFlight = 0;
      var detailPeak = 0;
      var statusInFlight = 0;
      var statusPeak = 0;
      when(() => member.getMemberDetail(any())).thenAnswer((_) async {
        detailInFlight++;
        detailPeak = detailPeak > detailInFlight ? detailPeak : detailInFlight;
        await gate.future;
        detailInFlight--;
        return _detail();
      });
      when(() => memberships.listMemberWaiverStatus(any(), any()))
          .thenAnswer((_) async {
        statusInFlight++;
        statusPeak = statusPeak > statusInFlight ? statusPeak : statusInFlight;
        await gate.future;
        statusInFlight--;
        return const [];
      });

      final cubit = build();
      cubit.startAsExistingMember();
      await cubit.pickPayerRow(_row('mem-payer', 'Marcus Bell'));
      cubit.confirmPayerMatch();
      when(() => member.createMember(any())).thenThrow(
        const DuplicateMemberException([
          DuplicateMemberMatch(
            memberId: 'mem-ella',
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

      cubit.continueToPlans();
      await _settle();

      expect(detailPeak, 2);
      expect(statusPeak, 2);
      gate.complete();
      await _settle();
      await cubit.close();
    });

    test('a THROWN plan read leaves the waiver skip intact — and still fails '
        'OPEN itself', () async {
      when(() => member.getMemberDetail(any())).thenThrow(Exception('down'));
      when(() => memberships.listMemberWaiverStatus('mem-old', gymId))
          .thenAnswer((_) async => [
                _status(waiverA, signed: true, meetsFloor: true),
                _status(waiverB, signed: false),
              ]);
      final cubit = await atWaiversAsExisting();

      // The waiver answer LANDED despite the sibling throwing.
      expect(cubit.state.waiverQueue, [waiverB]);
      // And the plan side kept its own fail-OPEN posture.
      expect(cubit.state.persons.first.hadTrial, isFalse);
      expect(cubit.state.persons.first.heldRecurringPlanIds, isEmpty);
      await cubit.close();
    });

    test('a THROWN waiver read leaves the plan history intact — and still fails '
        'CLOSED itself', () async {
      // A trial and a DIFFERENT recurring plan held, so both plan facts are
      // observable without closing the plan this walk picks.
      when(() => member.getMemberDetail(any())).thenAnswer(
        (_) async => _detailWith(
          const [
            ('plan-trial', 'trial', MembershipStatus.cancelled),
            ('plan-other', 'recurring', MembershipStatus.active),
          ],
        ),
      );
      when(() => memberships.listMemberWaiverStatus(any(), any()))
          .thenThrow(Exception('down'));
      final cubit = await atWaiversAsExisting();

      expect(cubit.state.waiverQueue, [waiverA, waiverB]);
      // The plan history LANDED despite the sibling throwing.
      expect(cubit.state.persons.first.hadTrial, isTrue);
      expect(cubit.state.persons.first.heldRecurringPlanIds, ['plan-other']);
      await cubit.close();
    });

    test('one MEMBER\'s failed reads never discard another member\'s answers',
        () async {
      // The payer's two reads both fail; the adopted payee's both land. A naive
      // gather would discard Ella's answers along with the payer's throw.
      when(() => member.getMemberDetail('mem-payer'))
          .thenThrow(Exception('down'));
      when(() => member.getMemberDetail('mem-ella')).thenAnswer(
        (_) async => _detailWith(
          const [('plan-trial', 'trial', MembershipStatus.cancelled)],
        ),
      );
      when(() => memberships.listMemberWaiverStatus('mem-payer', gymId))
          .thenThrow(Exception('down'));
      when(() => memberships.listMemberWaiverStatus('mem-ella', gymId))
          .thenAnswer((_) async => [
                _status(waiverA, signed: true, meetsFloor: true),
                _status(waiverB, signed: true, meetsFloor: true),
              ]);

      final cubit = build();
      cubit.startAsExistingMember();
      await cubit.pickPayerRow(_row('mem-payer', 'Marcus Bell'));
      cubit.confirmPayerMatch();
      when(() => member.createMember(any())).thenThrow(
        const DuplicateMemberException([
          DuplicateMemberMatch(
            memberId: 'mem-ella',
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

      cubit.continueToPlans();
      await _settle();
      // Ella's history landed even though the payer's read threw.
      expect(cubit.state.persons[1].hadTrial, isTrue);
      // The payer's own failed read fails OPEN rather than inheriting hers.
      expect(cubit.state.persons.first.hadTrial, isFalse);

      cubit.selectPlan(planId);
      cubit.continueFromPlans();
      cubit.selectPlan(planId);
      cubit.continueFromPlans();
      await _settle();

      // Ella owes nothing but the payer-authorization link.
      expect(cubit.state.payerAuthPending, isTrue);
      await cubit.signPayerAuth(signerName: 'Marcus Bell');
      await _settle();

      // Her waivers are skipped — her answer survived the payer's failure.
      expect(cubit.state.activePersonIndex, 0);
      // And the payer, whose read threw, is asked for BOTH.
      expect(cubit.state.waiverQueue, [waiverA, waiverB]);
      await cubit.close();
    });
  });

  group('a member created in this signup is never asked for the read',
      () {
    test('no history exists by construction, so no request is spent', () async {
      final cubit = build();
      cubit.startAsNewMember();
      cubit.submitDetails(
        firstName: 'Marcus',
        lastName: 'Bell',
        email: 'marcus.bell@gmail.com',
      );
      await cubit.submitExtraDetails();
      cubit.continueToPlans();
      await _settle();
      cubit.selectPlan(planId);
      cubit.continueFromPlans();
      await _settle();

      verifyNever(() => memberships.listMemberWaiverStatus(any(), any()));
      // And nothing is skipped for them either.
      expect(cubit.state.waiverQueue, [waiverA, waiverB]);
      await cubit.close();
    });
  });

  group('the group walk asks each person for what THEY owe', () {
    test('one person\'s compliance never covers the other\'s', () async {
      // The payer is compliant on A, the payee on B. Neither answer may leak
      // across: a state-root map would skip a child's signature for a parent's.
      when(() => memberships.listMemberWaiverStatus('mem-payer', gymId))
          .thenAnswer((_) async => [
                _status(waiverA, signed: true, meetsFloor: true),
                _status(waiverB, signed: true, meetsFloor: false),
              ]);
      when(() => memberships.listMemberWaiverStatus('mem-ella', gymId))
          .thenAnswer((_) async => [
                _status(waiverA, signed: false),
                _status(waiverB, signed: true, meetsFloor: true),
              ]);

      final cubit = build();
      cubit.startAsExistingMember();
      await cubit.pickPayerRow(_row('mem-payer', 'Marcus Bell'));
      cubit.confirmPayerMatch();
      // The payee is an EXISTING member too, adopted off their own 409.
      when(() => member.createMember(any())).thenThrow(
        const DuplicateMemberException([
          DuplicateMemberMatch(
            memberId: 'mem-ella',
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

      cubit.continueToPlans();
      await _settle();
      cubit.selectPlan(planId);
      cubit.continueFromPlans();
      cubit.selectPlan(planId);
      cubit.continueFromPlans();
      await _settle();

      // Ruling 9: the payee goes first, starting with their payer-auth link.
      expect(cubit.state.payerAuthPending, isTrue);
      await cubit.signPayerAuth(signerName: 'Marcus Bell');
      await _settle();

      // Ella owes only A — her B signature is compliant.
      expect(cubit.state.activePersonIndex, 1);
      expect(cubit.state.waiverQueue, [waiverA]);
      await cubit.signWaiver(signerName: 'Marcus Bell');
      await _settle();

      // Marcus owes only B — his A is compliant, his B sits below the floor.
      expect(cubit.state.step, KioskSignupStep.waivers);
      expect(cubit.state.activePersonIndex, 0);
      expect(cubit.state.waiverQueue, [waiverB]);
      await cubit.signWaiver(signerName: 'Marcus Bell');
      await _settle();

      expect(cubit.state.step, KioskSignupStep.card);
      // Exactly two signatures for the family, each against the right person.
      final signed = cubit.state.signedWaivers;
      expect(signed.length, 2);
      expect(signed[0].memberId, 'mem-ella');
      expect(signed[0].waiverId, waiverA);
      expect(signed[1].memberId, 'mem-payer');
      expect(signed[1].waiverId, waiverB);
      await cubit.close();
    });
  });
}

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

/// One row of `GET /waivers/signatures/by-member/{id}` — only the fields the
/// kiosk reads carry meaning here.
MemberWaiverStatus _status(
  String waiverId, {
  required bool signed,
  bool meetsFloor = false,
}) =>
    MemberWaiverStatus(
      waiverId: waiverId,
      name: waiverId,
      waiverType: WaiverType.custom,
      signed: signed,
      meetsFloor: meetsFloor,
    );

MembershipPlanResponse _plan() => MembershipPlanResponse(
      planId: 'plan-1',
      gymId: 'gym-1',
      planName: 'Unlimited',
      imageUrl: '',
      planType: PlanType.recurring,
      durationAmount: 1,
      isPublic: true,
      createdAt: DateTime.utc(2026),
      waiverIds: const ['waiver-a', 'waiver-b'],
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

WaiverResponse _waiver(String waiverId) => WaiverResponse(
      waiverId: waiverId,
      gymId: 'gym-1',
      name: waiverId,
      waiverType: WaiverType.custom,
      currentVersionId: 'version-$waiverId',
      currentVersionNumber: 1,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      currentVersion: WaiverVersionResponse(
        versionId: 'version-$waiverId',
        waiverId: waiverId,
        gymId: 'gym-1',
        versionNumber: 1,
        body: 'I accept the risks.',
        contentHash: 'hash-$waiverId',
        createdAt: DateTime.utc(2026),
      ),
    );

AuthorizedPayerWaiver _payerAuthWaiver() => const AuthorizedPayerWaiver(
      waiverId: 'waiver-payer-auth',
      versionId: 'version-payer-auth',
      name: 'Authorized payer agreement',
      body: 'I am authorised to pay.',
    );

/// A member whose history carries [rows] — one `(planId, planType, status)` per
/// membership; every other field is filler.
MemberDetailResponse _detailWith(
  List<(String, String, MembershipStatus)> rows,
) =>
    MemberDetailResponse(
      memberId: 'mem-old',
      gymId: 'gym-1',
      firstName: 'Marcus',
      lastName: 'Bell',
      membershipOverview: 'History',
      totalMonthlyRecurringPrice: 0,
      totalMembershipCount: rows.length,
      personalInfo: const PersonalInfo(),
      memberships: [
        for (final (planId, planType, status) in rows)
          MembershipInfo(
            planId: planId,
            planName: planId,
            planType: planType,
            status: status,
            itemId: 'item-$planId',
            paidByMemberId: 'mem-old',
            baseCost: 0,
            durationAmount: 1,
            durationUnit: 'month',
            totalPrice: 0,
            startDate: DateTime.utc(2025),
          ),
      ],
      retention: const Retention(
        classStreakWeeks: 0,
        pointsBalance: 0,
        videosWatched: 0,
      ),
    );

MemberDetailResponse _detail() => MemberDetailResponse(
      memberId: 'mem-old',
      gymId: 'gym-1',
      firstName: 'Marcus',
      lastName: 'Bell',
      membershipOverview: 'History',
      totalMonthlyRecurringPrice: 0,
      totalMembershipCount: 0,
      personalInfo: const PersonalInfo(),
      memberships: const [],
      retention: const Retention(
        classStreakWeeks: 0,
        pointsBalance: 0,
        videosWatched: 0,
      ),
    );
