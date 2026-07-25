import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:crm/features/kiosk/bloc/kiosk_session_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_state.dart';
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

class _MockMemberRepository extends Mock implements MemberRepository {}

class _MockMembershipsRepository extends Mock
    implements MembershipsRepository {}

class _MockMembersListRepository extends Mock
    implements MembersListRepository {}

class _MockKioskSessionCubit extends Mock implements KioskSessionCubit {}

class _MockManagementResponse extends Mock
    implements MembersManagementResponse {}

/// One trial to a member, at the KIOSK — a self-serve product rule, not a
/// backend one (staff can still grant a repeat trial from the CRM), enforced
/// entirely here off the member's own membership history.
///
/// ANY prior trial closes EVERY trial plan for that person; a blocked plan can
/// never become the selection (it would reach the review and fail at pay) but
/// its tap still explains; and the history read fails OPEN — a second trial
/// costs a free week the desk can undo, while turning away a legitimate
/// first-timer costs a paying customer.
void main() {
  const gymId = 'gym-1';
  const trialPlan = 'plan-trial';
  const monthlyPlan = 'plan-monthly';
  const secondTrialPlan = 'plan-trial-2';
  final t0 = DateTime.utc(2026, 1, 1, 18);

  late _MockMemberRepository member;
  late _MockMembershipsRepository memberships;
  late _MockMembersListRepository membersList;
  late _MockKioskSessionCubit session;

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

    when(() => memberships.listPlans(any())).thenAnswer(
      (_) async => [
        _plan(trialPlan, 'Two-week trial', PlanType.trial),
        _plan(secondTrialPlan, 'Beginner trial', PlanType.trial),
        _plan(monthlyPlan, 'Unlimited', PlanType.recurring),
      ],
    );
    when(() => member.createMember(any())).thenAnswer((_) async => 'mem-new');
    when(() => member.updateMember(any(), any()))
        .thenAnswer((_) async => _MockManagementResponse());
    when(() => membersList.getMembersList(any()))
        .thenAnswer((_) async => _page(const []));
    when(() => member.getMemberDetail(any()))
        .thenAnswer((_) async => _detail(const []));
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
  /// plan grid. Their history is whatever [history] says.
  Future<KioskSignupCubit> atPlansAsExisting(
    List<MembershipInfo> history,
  ) async {
    when(() => member.getMemberDetail(any()))
        .thenAnswer((_) async => _detail(history));
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

  group('any prior trial closes every trial', () {
    test('a member who took ONE trial has BOTH trial plans blocked', () async {
      final cubit = await atPlansAsExisting([_membership(trialPlan, 'trial')]);

      expect(cubit.state.payer.hadTrial, isTrue);
      // The rule is per MEMBER, so the trial they never took is closed too.
      expect(
        cubit.state.planBlockReason(cubit.state.plans
            .firstWhere((p) => p.planId == trialPlan)),
        KioskPlanBlockReason.trialUsed,
      );
      expect(
        cubit.state.planBlockReason(cubit.state.plans
            .firstWhere((p) => p.planId == secondTrialPlan)),
        KioskPlanBlockReason.trialUsed,
      );
      expect(
        cubit.state.planBlockReason(cubit.state.plans
            .firstWhere((p) => p.planId == monthlyPlan)),
        isNull,
      );
      await cubit.close();
    });

    test('a CANCELLED or long-finished trial still counts', () async {
      // No lifecycle filter here, matching the backend.
      final cubit = await atPlansAsExisting([
        _membership(
          trialPlan,
          'trial',
          status: MembershipStatus.cancelled,
          cancelDate: DateTime.utc(2025, 3),
        ),
      ]);
      expect(cubit.state.payer.hadTrial, isTrue);
      await cubit.close();
    });

    test('a member with only RECURRING history keeps every trial', () async {
      final cubit =
          await atPlansAsExisting([_membership(monthlyPlan, 'recurring')]);

      expect(cubit.state.payer.hadTrial, isFalse);
      // Two independent rules: no trial in their history leaves every TRIAL
      // plan open, while the recurring plan they hold is closed by the other
      // one (see `kiosk_signup_plan_block_test.dart`).
      for (final plan in cubit.state.plans) {
        if (plan.planId == monthlyPlan) continue;
        expect(cubit.state.planBlockReason(plan), isNull);
      }
      expect(
        cubit.state.planBlockReason(cubit.state.plans
            .firstWhere((p) => p.planId == monthlyPlan)),
        KioskPlanBlockReason.alreadyOnPlan,
      );
      await cubit.close();
    });

    test('a member CREATED here is never asked — no history by construction',
        () async {
      final cubit = build();
      cubit.startAsNewMember();
      cubit.submitDetails(
        firstName: 'Marcus',
        lastName: 'Bell',
        email: 'marcus.bell@gmail.com',
      );
      await cubit.submitExtraDetails();
      cubit.continueToPlans();
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.payer.hadTrial, isFalse);
      verifyNever(() => member.getMemberDetail(any()));
      await cubit.close();
    });

    test('FAILS OPEN — an unreadable history leaves the trial on offer',
        () async {
      when(() => member.getMemberDetail(any())).thenThrow(Exception('down'));
      final cubit = build();
      cubit.startAsExistingMember();
      await cubit.pickPayerRow(_row('mem-old', 'Marcus Bell'));
      cubit.confirmPayerMatch();
      cubit.continueToPlans();
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.payer.hadTrial, isFalse);
      cubit.selectPlan(trialPlan);
      expect(cubit.state.payer.selectedPlanId, trialPlan);
      expect(cubit.state.planBlockActive, isNull);
      await cubit.close();
    });
  });

  group('a blocked trial explains instead of selecting', () {
    test('tapping it opens the popup and sets NO selection', () async {
      final cubit = await atPlansAsExisting([_membership(trialPlan, 'trial')]);
      cubit.selectPlan(trialPlan);

      expect(cubit.state.payer.selectedPlanId, isNull);
      expect(cubit.state.planBlockActive, KioskPlanBlockReason.trialUsed);
      // Never a silent no-op — the answer is one tap away.
      expect(cubit.state.popupCountdown, kKioskSignupPopupHold.inSeconds);
      await cubit.close();
    });

    test('"Pick a membership" dismisses, and a real plan then selects',
        () async {
      final cubit = await atPlansAsExisting([_membership(trialPlan, 'trial')]);
      cubit.selectPlan(trialPlan);
      cubit.dismissPlanBlock();

      expect(cubit.state.planBlockActive, isNull);
      expect(cubit.state.popupCountdown, 0);
      expect(cubit.state.payer.selectedPlanId, isNull);

      cubit.selectPlan(monthlyPlan);
      expect(cubit.state.payer.selectedPlanId, monthlyPlan);
      expect(cubit.state.planBlockActive, isNull);
      await cubit.close();
    });

    test('"Get help at the desk" is the terminal handoff, released once',
        () async {
      final cubit = await atPlansAsExisting([_membership(trialPlan, 'trial')]);
      cubit.selectPlan(trialPlan);
      cubit.planBlockHelp();

      expect(cubit.state.step, KioskSignupStep.stop);
      expect(cubit.state.stopReason, KioskSignupStopReason.trialAlreadyUsed);
      expect(cubit.state.planBlockActive, isNull);
      verify(() => session.endFlow()).called(1);
      await cubit.close();
      // Still exactly once after the teardown — the latch holds.
      verifyNever(() => session.endFlow());
    });

    test('a trial picked before the answer landed is dropped with it',
        () async {
      // The history read is in flight while the member taps: the pick lands,
      // then the answer arrives and must take it back off.
      when(() => member.getMemberDetail(any())).thenAnswer(
        (_) async => _detail([_membership(trialPlan, 'trial')]),
      );
      final cubit = build();
      cubit.startAsExistingMember();
      await cubit.pickPayerRow(_row('mem-old', 'Marcus Bell'));
      cubit.confirmPayerMatch();
      cubit.continueToPlans();
      cubit.selectPlan(trialPlan);
      expect(cubit.state.payer.selectedPlanId, trialPlan);

      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.payer.hadTrial, isTrue);
      expect(cubit.state.payer.selectedPlanId, isNull);
      await cubit.close();
    });
  });

  group('the popup cannot hold the iPad forever', () {
    test('the countdown expires to home and releases the flow exactly once',
        () {
      fakeAsync((async) {
        when(() => member.getMemberDetail(any())).thenAnswer(
          (_) async => _detail([_membership(trialPlan, 'trial')]),
        );
        final cubit = build();
        cubit.startAsExistingMember();
        cubit.pickPayerRow(_row('mem-old', 'Marcus Bell'));
        async.flushMicrotasks();
        cubit.confirmPayerMatch();
        cubit.continueToPlans();
        async.flushMicrotasks();
        cubit.selectPlan(trialPlan);
        expect(cubit.state.planBlockActive, KioskPlanBlockReason.trialUsed);

        // Halfway: still up, and visibly counting.
        async.elapse(const Duration(seconds: 30));
        expect(cubit.state.popupCountdown, 30);
        expect(cubit.state.abandoned, isFalse);

        async.elapse(kKioskSignupPopupHold);
        // The ordinary abandon path: `KioskSignupScreen` turns `abandoned`
        // into `goHome()`, and the ONE latch releases the flow count.
        expect(cubit.state.abandoned, isTrue);
        expect(cubit.state.planBlockActive, isNull);
        verify(() => session.endFlow()).called(1);
        cubit.close();
        async.flushTimers();
      });
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
        price: type == PlanType.trial ? 0 : 14900,
        isActive: true,
        createdAt: DateTime.utc(2026),
      ),
    );

/// One row of the member's own membership history, exactly as the billing
/// detail hands it over — `planType` is a plain string there, not the enum.
MembershipInfo _membership(
  String planId,
  String planType, {
  MembershipStatus status = MembershipStatus.active,
  DateTime? cancelDate,
}) =>
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
      cancelDate: cancelDate,
    );

MemberDetailResponse _detail(List<MembershipInfo> memberships) =>
    MemberDetailResponse(
      memberId: 'mem-old',
      gymId: 'gym-1',
      firstName: 'Marcus',
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
