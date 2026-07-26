import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:crm/features/kiosk/bloc/kiosk_session_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_state.dart';
import 'package:crm/features/kiosk/presentation/kiosk_plan_block_copy.dart';
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

/// A recurring membership the member already holds is BLOCKED at pick — the
/// backend's per-plan conflict guard would otherwise 400, which the kiosk can
/// only surface as a generic retryable stop (and in a group, one held plan
/// kills the whole family's signup).
///
/// The rule mirrors that guard exactly — `recurring` at the view's
/// `{active, frozen}`, keyed on the PLAN — which takes THREE client statuses,
/// because `overdue` is a Python-derived DISPLAY status masking a raw `active`
/// row the guard still rejects. The held set lives on the PERSON, so a group
/// cannot leak one member's membership onto another's turn, and the read FAILS
/// OPEN: on a failure the kiosk knows nobody's plans, so failing closed would
/// block the whole grid.
void main() {
  const gymId = 'gym-1';
  const unlimited = 'plan-unlimited';
  const kids = 'plan-kids';
  const pack = 'plan-pack';
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

    when(() => memberships.listPlans(any())).thenAnswer(
      (_) async => [
        _plan(unlimited, 'Unlimited', PlanType.recurring),
        _plan(kids, 'Kids Program', PlanType.recurring),
        _plan(pack, '10-Class Pack', PlanType.oneTime),
      ],
    );
    when(() => member.createMember(any())).thenAnswer((_) async => MemberCreateResult(
          memberId: 'mem-new',
          invite: InviteOutcome.queued,
        ));
    when(() => member.updateMember(any(), any()))
        .thenAnswer((_) async => _MockManagementResponse());
    when(() => membersList.getMembersList(any()))
        .thenAnswer((_) async => _page(const []));
    when(() => member.getMemberDetail(any()))
        .thenAnswer((_) async => _detail('mem-old', 'Marcus', const []));
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

  /// An EXISTING member adopted through the identify search, standing on the
  /// plan grid with [history] as their own membership history.
  Future<KioskSignupCubit> atPlansAsExisting(
    List<MembershipInfo> history,
  ) async {
    when(() => member.getMemberDetail(any()))
        .thenAnswer((_) async => _detail('mem-old', 'Marcus', history));
    final cubit = build();
    cubit.startAsExistingMember();
    await cubit.pickPayerRow(_row('mem-old', 'Marcus Bell'));
    cubit.confirmPayerMatch();
    await Future<void>.delayed(Duration.zero);
    cubit.continueToPlans();
    await Future<void>.delayed(Duration.zero);
    expect(cubit.state.step, KioskSignupStep.plans);
    return cubit;
  }

  MembershipPlanResponse planOf(KioskSignupCubit cubit, String id) =>
      cubit.state.plans.firstWhere((p) => p.planId == id);

  group('the rule mirrors the backend SQL exactly', () {
    test('an ACTIVE recurring plan they hold is blocked; a DIFFERENT recurring '
        'plan is not', () async {
      final cubit = await atPlansAsExisting([
        _membership(unlimited, 'recurring'),
      ]);

      expect(cubit.state.payer.heldRecurringPlanIds, [unlimited]);
      expect(
        cubit.state.planBlockReason(planOf(cubit, unlimited)),
        KioskPlanBlockReason.alreadyOnPlan,
      );
      // The conflict is per PLAN (`plan_id = ANY(:plan_ids)`): a member on one
      // recurring plan may freely buy another.
      expect(cubit.state.planBlockReason(planOf(cubit, kids)), isNull);
      cubit.selectPlan(kids);
      expect(cubit.state.payer.selectedPlanId, kids);
      expect(cubit.state.planBlockActive, isNull);
      await cubit.close();
    });

    test('a FROZEN recurring plan blocks too, and never says "frozen"',
        () async {
      final cubit = await atPlansAsExisting([
        _membership(unlimited, 'recurring', status: MembershipStatus.frozen),
      ]);

      // The SQL's status set is exactly ('active','frozen').
      expect(
        cubit.state.planBlockReason(planOf(cubit, unlimited)),
        KioskPlanBlockReason.alreadyOnPlan,
      );
      // Billing state is never printed in a lobby: a frozen plan is blocked and
      // labelled identically to an active one.
      final notice = kioskHeldPlanNotice(cubit.state)!;
      expect(notice, contains('Unlimited'));
      expect(notice.toLowerCase(), isNot(contains('frozen')));
      expect(
        kioskPlanBlockTag(KioskPlanBlockReason.alreadyOnPlan),
        'You have this',
      );
      await cubit.close();
    });

    test('OVERDUE blocks — the view has no such status, so the guard sees the '
        'raw ACTIVE row and rejects the sale', () async {
      final cubit = await atPlansAsExisting([
        _membership(unlimited, 'recurring', status: MembershipStatus.overdue),
      ]);

      // `overdue` is not a DB status: the `member_memberships_status` view
      // emits only cancelled/ended/frozen/active and a past-due row falls
      // through to `active`, which the guard rejects. The client enum SPLITS
      // that `active`, so matching only the SQL's two literals under-blocks.
      expect(cubit.state.payer.heldRecurringPlanIds, [unlimited]);
      expect(
        cubit.state.planBlockReason(planOf(cubit, unlimited)),
        KioskPlanBlockReason.alreadyOnPlan,
      );
      // Money owed is the desk's conversation, not a lobby iPad's.
      final notice = kioskHeldPlanNotice(cubit.state)!;
      expect(notice, contains('Unlimited'));
      expect(notice.toLowerCase(), isNot(contains('overdue')));
      await cubit.close();
    });

    test('a held ONE-TIME pack and a held TRIAL never block their own plan',
        () async {
      final cubit = await atPlansAsExisting([
        _membership(pack, 'one_time'),
        _membership(kids, 'trial'),
      ]);

      // `plan_type = 'recurring'` is the SQL's own filter — one_time and trial
      // packs are allowed to STACK.
      expect(cubit.state.payer.heldRecurringPlanIds, isEmpty);
      expect(cubit.state.planBlockReason(planOf(cubit, pack)), isNull);
      // The held trial closes every TRIAL plan through the other rule, but
      // `kids` is recurring, so it stays open.
      expect(cubit.state.payer.hadTrial, isTrue);
      expect(cubit.state.planBlockReason(planOf(cubit, kids)), isNull);
      await cubit.close();
    });

    test('FAILS OPEN — an unreadable history blocks nothing at all', () async {
      when(() => member.getMemberDetail(any())).thenThrow(Exception('down'));
      final cubit = build();
      cubit.startAsExistingMember();
      await cubit.pickPayerRow(_row('mem-old', 'Marcus Bell'));
      cubit.confirmPayerMatch();
      cubit.continueToPlans();
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.payer.heldRecurringPlanIds, isEmpty);
      for (final plan in cubit.state.plans) {
        expect(cubit.state.planBlockReason(plan), isNull);
      }
      expect(kioskHeldPlanNotice(cubit.state), isNull);
      await cubit.close();
    });
  });

  group('a blocked plan explains instead of selecting', () {
    test('tapping it opens the popup, names the plan, and sets NO selection',
        () async {
      final cubit = await atPlansAsExisting([
        _membership(unlimited, 'recurring'),
      ]);
      cubit.selectPlan(unlimited);

      expect(cubit.state.payer.selectedPlanId, isNull);
      expect(
        cubit.state.planBlockActive,
        KioskPlanBlockReason.alreadyOnPlan,
      );
      expect(cubit.state.popupCountdown, kKioskSignupPopupHold.inSeconds);
      // The popup NAMES the plan because this rule is per plan (the trial popup
      // deliberately does not — its rule is per member).
      final body = kioskPlanBlockBody(
        cubit.state,
        KioskPlanBlockReason.alreadyOnPlan,
      );
      expect(body, contains('Unlimited'));
      await cubit.close();
    });

    test('"Get help at the desk" stops on the already-on-plan reason', () async {
      final cubit = await atPlansAsExisting([
        _membership(unlimited, 'recurring'),
      ]);
      cubit.selectPlan(unlimited);
      cubit.planBlockHelp();

      expect(cubit.state.step, KioskSignupStep.stop);
      expect(cubit.state.stopReason, KioskSignupStopReason.alreadyOnPlan);
      expect(cubit.state.stopReason!.isRetryable, isFalse);
      // A terminal reason releases the flow count on entry, exactly once.
      verify(() => session.endFlow()).called(1);
      await cubit.close();
      verifyNever(() => session.endFlow());
    });

    test('a pick made before the answer landed is dropped with it', () async {
      when(() => member.getMemberDetail(any())).thenAnswer(
        (_) async => _detail('mem-old', 'Marcus', [
          _membership(unlimited, 'recurring'),
        ]),
      );
      final cubit = build();
      cubit.startAsExistingMember();
      await cubit.pickPayerRow(_row('mem-old', 'Marcus Bell'));
      cubit.confirmPayerMatch();
      cubit.continueToPlans();
      cubit.selectPlan(unlimited);
      expect(cubit.state.payer.selectedPlanId, unlimited);

      await Future<void>.delayed(Duration.zero);
      // Otherwise the blocked plan rides to the review and dead-ends there.
      expect(cubit.state.payer.selectedPlanId, isNull);
      await cubit.close();
    });
  });

  group('the group guard is structural', () {
    test('advancing the active person changes BOTH the notice and the blocked '
        'set', () async {
      // The parent holds Unlimited; the child holds Kids Program.
      when(() => member.getMemberDetail('mem-old')).thenAnswer(
        (_) async => _detail('mem-old', 'Marcus', [
          _membership(unlimited, 'recurring'),
        ]),
      );
      when(() => member.getMemberDetail('mem-kid')).thenAnswer(
        (_) async => _detail('mem-kid', 'Ella', [
          _membership(kids, 'recurring'),
        ]),
      );
      final cubit = build();
      cubit.startAsExistingMember();
      await cubit.pickPayerRow(_row('mem-old', 'Marcus Bell'));
      cubit.confirmPayerMatch();
      // The child is an existing member too, adopted off their own 409.
      when(() => member.createMember(any())).thenThrow(
        const DuplicateMemberException([
          DuplicateMemberMatch(
            memberId: 'mem-kid',
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
      expect(cubit.state.isGroup, isTrue);
      cubit.continueToPlans();
      await Future<void>.delayed(Duration.zero);

      // The parent's turn.
      expect(cubit.state.activePersonIndex, 0);
      expect(
        cubit.state.planBlockReason(planOf(cubit, unlimited)),
        KioskPlanBlockReason.alreadyOnPlan,
      );
      expect(cubit.state.planBlockReason(planOf(cubit, kids)), isNull);
      final parentNotice = kioskHeldPlanNotice(cubit.state)!;
      expect(parentNotice, contains('Unlimited'));
      expect(parentNotice, isNot(contains('Kids Program')));

      cubit.selectPlan(kids);
      cubit.continueFromPlans();
      expect(cubit.state.activePersonIndex, 1);

      // The child's turn: the sets FLIP. Storing the held ids on the PERSON is
      // what makes that leak unrepresentable rather than merely avoided.
      expect(cubit.state.planBlockReason(planOf(cubit, kids)),
          KioskPlanBlockReason.alreadyOnPlan);
      expect(cubit.state.planBlockReason(planOf(cubit, unlimited)), isNull);
      final childNotice = kioskHeldPlanNotice(cubit.state)!;
      expect(childNotice, contains('Ella'));
      expect(childNotice, contains('Kids Program'));
      expect(childNotice, isNot(contains('Unlimited')));
      await cubit.close();
    });
  });
}

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

MembershipPlanResponse _plan(String id, String name, PlanType type) =>
    MembershipPlanResponse(
      planId: id,
      gymId: 'gym-1',
      planName: name,
      imageUrl: '',
      planType: type,
      durationAmount: 1,
      isPublic: true,
      createdAt: DateTime.utc(2026),
      waiverIds: const [],
      activePrice: MembershipPlanPriceResponse(
        priceId: 'price-$id',
        planId: id,
        gymId: 'gym-1',
        stripePriceId: 'price_stripe_$id',
        price: 14900,
        isActive: true,
        createdAt: DateTime.utc(2026),
      ),
    );

/// One row of a member's own membership history, exactly as the billing detail
/// hands it over — `planType` is a plain string there, not the enum.
MembershipInfo _membership(
  String planId,
  String planType, {
  MembershipStatus status = MembershipStatus.active,
}) =>
    MembershipInfo(
      planId: planId,
      planName: planId,
      planType: planType,
      status: status,
      itemId: 'item-$planId',
      paidByMemberId: 'mem-old',
      baseCost: 14900,
      durationAmount: 1,
      durationUnit: 'month',
      totalPrice: 14900,
      startDate: DateTime.utc(2025),
    );

MemberDetailResponse _detail(
  String memberId,
  String firstName,
  List<MembershipInfo> memberships,
) =>
    MemberDetailResponse(
      memberId: memberId,
      gymId: 'gym-1',
      firstName: firstName,
      lastName: 'Bell',
      membershipOverview: 'History',
      totalMonthlyRecurringPrice: 0,
      totalMembershipCount: memberships.length,
      personalInfo: const PersonalInfo(),
      memberships: memberships,
      retention: const Retention(
        classStreakWeeks: 0,
        pointsBalance: 0,
        videosWatched: 0,
      ),
    );
