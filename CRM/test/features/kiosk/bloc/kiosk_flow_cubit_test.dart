import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:crm/features/check_in/data/models/check_in_request.dart';
import 'package:crm/features/check_in/data/models/check_in_response.dart';
import 'package:crm/features/check_in/data/models/check_in_warning.dart';
import 'package:crm/features/kiosk/bloc/kiosk_flow_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_flow_state.dart';
import 'package:crm/features/kiosk/bloc/kiosk_session_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_session_state.dart';
import 'package:crm/features/member_details/data/models/member_detail_response.dart';
import 'package:crm/features/member_details/data/models/retention.dart';
import 'package:crm/features/member_details/data/repositories/member_repository.dart';
import 'package:crm/features/members_list/data/models/crm_members_list_request.dart';
import 'package:crm/features/members_list/data/models/crm_members_list_response.dart';
import 'package:crm/features/members_list/data/models/member_row.dart';
import 'package:crm/features/members_list/data/models/members_list_filters.dart';
import 'package:crm/features/members_list/data/models/members_list_view.dart';
import 'package:crm/features/members_list/data/models/membership_status.dart';
import 'package:crm/features/members_list/data/repositories/members_list_repository.dart';
import 'package:crm/features/rewards/data/models/reward_response.dart';
import 'package:crm/features/rewards/data/repositories/rewards_repository.dart';
import 'package:crm/features/schedule/data/models/effective_class_instance.dart';
import 'package:crm/features/schedule/data/repositories/schedule_repository.dart';

class _MockMembersListRepository extends Mock
    implements MembersListRepository {}

class _MockScheduleRepository extends Mock implements ScheduleRepository {}

class _MockMemberRepository extends Mock implements MemberRepository {}

class _MockRewardsRepository extends Mock implements RewardsRepository {}

class _MockMemberDetail extends Mock implements MemberDetailResponse {}

class _MockKioskSessionCubit extends Mock implements KioskSessionCubit {}

/// The kiosk check-in lane's flow cubit: it gates a new flow on the session's
/// [KioskSessionState.canStartFlow], marks it with begin/endFlow (grace-window
/// bookkeeping), records the `is_member: true` check-in, and abandons a stale
/// draft after 5 minutes of inactivity. The repositories are mocked; a fixed
/// clock + `fakeAsync` drive the idle timer deterministically.
void main() {
  const gymId = 'gym-1';
  final t0 = DateTime.utc(2026, 1, 1, 18);

  final activeState = KioskSessionState(
    status: KioskStatus.active,
    deadline: t0.add(const Duration(hours: 12)),
  );
  const lockedState = KioskSessionState.inactive();

  const member1 = AllViewRow(
    memberId: 'mem-1',
    name: 'Marcus Bell',
    membershipStatus: MembershipStatus.active,
    membershipText: 'Monthly',
  );

  final occ1 = EffectiveClassInstance(
    classId: 'class-1',
    gymId: gymId,
    className: 'Muay Thai Fundamentals',
    classDate: DateTime(2026, 1, 1),
    originalDate: DateTime(2026, 1, 1),
    originalTime: '18:00:00',
    occurredAt: t0,
    resolvedClassTime: '18:00:00',
    resolvedDurationMinutes: 60,
    pointsWorth: 15,
    isCancelled: false,
    hasInstanceException: false,
    hasRangeException: false,
  );

  const recorded = CheckInResponse(
    logId: 'log-1',
    memberId: 'mem-1',
    classId: 'class-1',
    alreadyCheckedIn: false,
    pointsAwarded: 15,
    classStreakWeeks: 3,
  );

  const rejected = CheckInResponse(
    logId: null,
    memberId: 'mem-1',
    classId: 'class-1',
    alreadyCheckedIn: false,
    skipReason: CheckInWarning.overCapacity,
  );

  // Deliberately pricey-first so the cubit's cheapest-first sort is observable.
  final rewardPricey = RewardResponse(
    rewardId: 'r-pricey',
    gymId: gymId,
    title: '1-on-1 PT session',
    pointCost: 2500,
    priceLabel: '50% off',
    isActive: true,
    createdAt: t0,
  );
  final rewardCheap = RewardResponse(
    rewardId: 'r-cheap',
    gymId: gymId,
    title: 'Bring a friend',
    pointCost: 1000,
    priceLabel: 'Free',
    isActive: true,
    createdAt: t0,
  );

  late _MockMembersListRepository members;
  late _MockScheduleRepository schedule;
  late _MockMemberRepository member;
  late _MockRewardsRepository rewards;
  late _MockMemberDetail detail;
  late _MockKioskSessionCubit session;

  setUpAll(() {
    registerFallbackValue(DateTime(2026));
    registerFallbackValue(
      const CrmMembersListRequest(gymId: gymId, view: MembersListView.all),
    );
    registerFallbackValue(
      const CheckInRequest(
        memberId: 'm',
        gymId: 'g',
        classId: 'c',
        occurrenceDate: '2026-01-01',
        occurrenceTime: '18:00:00',
      ),
    );
  });

  setUp(() {
    members = _MockMembersListRepository();
    schedule = _MockScheduleRepository();
    member = _MockMemberRepository();
    rewards = _MockRewardsRepository();
    detail = _MockMemberDetail();
    session = _MockKioskSessionCubit();
    when(() => session.state).thenReturn(activeState);
    when(() => schedule.listEffectiveInstances(any(), any(), any()))
        .thenAnswer((_) async => <EffectiveClassInstance>[occ1]);
    when(() => detail.retention).thenReturn(
      const Retention(
        classStreakWeeks: 3,
        pointsBalance: 2150,
        videosWatched: 0,
      ),
    );
    when(() => member.getMemberDetail(any()))
        .thenAnswer((_) async => detail);
    when(() => rewards.listRewards(any(),
            includeInactive: any(named: 'includeInactive')))
        .thenAnswer((_) async => [rewardPricey, rewardCheap]);
  });

  KioskFlowCubit build() => KioskFlowCubit(
        membersRepository: members,
        scheduleRepository: schedule,
        memberRepository: member,
        rewardsRepository: rewards,
        session: session,
        gymId: gymId,
        now: () => t0,
      );

  CrmMembersListResponse resultsOf(List<MemberRow> rows) =>
      CrmMembersListResponse(
        view: MembersListView.all,
        filters: const MembersListFilters(),
        data: rows,
      );

  // A minimal occurrence at [occurredAt] for the checkinable-now filter test.
  EffectiveClassInstance occAt(
    String id,
    DateTime occurredAt, {
    int duration = 60,
    bool cancelled = false,
  }) =>
      EffectiveClassInstance(
        classId: id,
        gymId: gymId,
        className: id,
        classDate: DateTime(2026, 1, 1),
        originalDate: DateTime(2026, 1, 1),
        originalTime: '00:00:00',
        occurredAt: occurredAt,
        resolvedClassTime: '00:00:00',
        resolvedDurationMinutes: duration,
        pointsWorth: 10,
        isCancelled: cancelled,
        hasInstanceException: false,
        hasRangeException: false,
      );

  group('name search', () {
    test('debounces, then populates results from the roster', () {
      fakeAsync((async) {
        when(() => members.getMembersList(any()))
            .thenAnswer((_) async => resultsOf([member1]));
        final cubit = build();

        cubit.search('mar');
        expect(cubit.state.searchResults, isEmpty); // not yet — debouncing

        async.elapse(kKioskSearchDebounce);
        async.flushMicrotasks();
        expect(cubit.state.searchResults, [member1]);
        cubit.close();
      });
    });
  });

  group('starting a flow (gated on canStartFlow)', () {
    blocTest<KioskFlowCubit, KioskFlowState>(
      'selectMember advances to class pick and begins the flow when active',
      build: build,
      act: (cubit) => cubit.selectMember(member1),
      verify: (cubit) {
        expect(cubit.state.view, KioskView.classPick);
        expect(cubit.state.selectedMember, member1);
        verify(() => session.beginFlow()).called(1);
      },
    );

    blocTest<KioskFlowCubit, KioskFlowState>(
      'selectMember shows the closing screen and starts NO flow when the '
      'session cannot start (locked)',
      setUp: () => when(() => session.state).thenReturn(lockedState),
      build: build,
      act: (cubit) => cubit.selectMember(member1),
      expect: () => [
        isA<KioskFlowState>().having((s) => s.view, 'view', KioskView.closing),
      ],
      verify: (_) => verifyNever(() => session.beginFlow()),
    );
  });

  group('recording the check-in', () {
    blocTest<KioskFlowCubit, KioskFlowState>(
      'a recorded check-in advances to the glance and ends the flow',
      setUp: () => when(() => member.checkInMember(any()))
          .thenAnswer((_) async => recorded),
      build: build,
      act: (cubit) async {
        cubit.selectMember(member1);
        await cubit.selectClass(occ1);
      },
      verify: (cubit) {
        expect(cubit.state.view, KioskView.checkedIn);
        expect(cubit.state.checkInResult?.pointsAwarded, 15);
        expect(cubit.state.checkInResult?.classStreakWeeks, 3);
        verify(() => session.beginFlow()).called(1);
        verify(() => session.endFlow()).called(1);
      },
    );

    blocTest<KioskFlowCubit, KioskFlowState>(
      'a gate rejection (skip_reason) routes to the reasoned blocked screen '
      'and ends the flow',
      setUp: () => when(() => member.checkInMember(any()))
          .thenAnswer((_) async => rejected),
      build: build,
      act: (cubit) async {
        cubit.selectMember(member1);
        await cubit.selectClass(occ1);
      },
      verify: (cubit) {
        expect(cubit.state.view, KioskView.blocked);
        expect(cubit.state.blockedReason, CheckInWarning.overCapacity);
        expect(cubit.state.checkInFailed, isFalse);
        verify(() => session.endFlow()).called(1);
      },
    );

    blocTest<KioskFlowCubit, KioskFlowState>(
      'a failed check-in call routes to the blocked screen (checkInFailed) '
      'and still ends the flow',
      setUp: () => when(() => member.checkInMember(any()))
          .thenThrow(Exception('network down')),
      build: build,
      act: (cubit) async {
        cubit.selectMember(member1);
        await cubit.selectClass(occ1);
      },
      verify: (cubit) {
        expect(cubit.state.view, KioskView.blocked);
        expect(cubit.state.checkInFailed, isTrue);
        verify(() => session.endFlow()).called(1);
      },
    );
  });

  group('class pick — checkinable-now filter (kiosk-local)', () {
    // Fixed now = t0 = 18:00. The filter keeps in-session + early-window
    // occurrences and drops already-ended, out-of-window, and cancelled ones.
    blocTest<KioskFlowCubit, KioskFlowState>(
      'drops ended / out-of-window / cancelled classes and orders the rest '
      'current-then-soonest',
      setUp: () {
        final ended = occAt('ended', t0.subtract(const Duration(hours: 2)));
        final soon = occAt('soon', t0.add(const Duration(hours: 1)));
        final later = occAt('later', t0.add(const Duration(hours: 3)));
        final cancelled = occAt('cancelled', t0, cancelled: true);
        when(() => schedule.listEffectiveInstances(any(), any(), any()))
            .thenAnswer((_) async => [later, ended, soon, occ1, cancelled]);
      },
      build: build,
      act: (cubit) async {
        cubit.selectMember(member1);
        await Future<void>.delayed(const Duration(milliseconds: 20));
      },
      verify: (cubit) {
        // occ1 (18:00, in session) then soon (19:00, within the 2h window);
        // ended (17:00 end), later (21:00 start), and cancelled all dropped.
        expect(
          cubit.state.classes.map((c) => c.classId).toList(),
          ['class-1', 'soon'],
        );
      },
    );
  });

  group('stale check-in response guard (SEC-5)', () {
    test('a response landing after the member left does not leak the glance '
        'over the next person', () async {
      final gate = Completer<CheckInResponse>();
      when(() => member.checkInMember(any())).thenAnswer((_) => gate.future);
      final cubit = build();

      cubit.selectMember(member1);
      await Future<void>.delayed(Duration.zero); // class load settles
      final pending = cubit.selectClass(occ1); // check-in awaits the gate
      expect(cubit.state.view, KioskView.checkingIn);

      cubit.goHome(); // the member walks away before the response arrives
      expect(cubit.state.view, KioskView.home);

      gate.complete(recorded); // the stale response finally lands
      await pending;

      expect(cubit.state.view, KioskView.home); // NOT the prior glance
      expect(cubit.state.checkInResult, isNull);
      // Ended exactly once (by goHome), never double-ended by the stale branch.
      verify(() => session.endFlow()).called(1);
      await cubit.close();
    });
  });

  group('5-minute flow-idle guard', () {
    test('warns with a countdown, then abandons the draft and returns home',
        () {
      fakeAsync((async) {
        final cubit = build();
        cubit.selectMember(member1);
        async.flushMicrotasks(); // let the class load settle
        expect(cubit.state.view, KioskView.classPick);

        async.elapse(kKioskIdleTimeout);
        expect(cubit.state.idleWarningActive, isTrue);
        expect(cubit.state.idleCountdown, kKioskIdleCountdown.inSeconds);

        async.elapse(kKioskIdleCountdown);
        expect(cubit.state.view, KioskView.home);
        expect(cubit.state.selectedMember, isNull);
        expect(cubit.state.idleWarningActive, isFalse);
        verify(() => session.endFlow()).called(1);
        cubit.close();
      });
    });

    test('any activity dismisses the warning and resets the idle clock', () {
      fakeAsync((async) {
        final cubit = build();
        cubit.selectMember(member1);
        async.flushMicrotasks();

        async.elapse(kKioskIdleTimeout);
        expect(cubit.state.idleWarningActive, isTrue);

        cubit.registerActivity(); // "I'm still here"
        expect(cubit.state.idleWarningActive, isFalse);
        expect(cubit.state.view, KioskView.classPick); // draft kept

        // The clock is reset: elapsing just under the timeout does not re-warn.
        async.elapse(kKioskIdleTimeout - const Duration(seconds: 1));
        expect(cubit.state.idleWarningActive, isFalse);
        cubit.close();
      });
    });
  });

  group('retention glance (Phase C2)', () {
    blocTest<KioskFlowCubit, KioskFlowState>(
      'a recorded check-in loads the points balance + cheapest-first reward '
      'catalog onto the glance',
      setUp: () => when(() => member.checkInMember(any()))
          .thenAnswer((_) async => recorded),
      build: build,
      act: (cubit) async {
        cubit.selectMember(member1);
        await cubit.selectClass(occ1);
        // Let the (unawaited) balance + catalog fetches settle.
        await Future<void>.delayed(const Duration(milliseconds: 20));
      },
      verify: (cubit) {
        expect(cubit.state.view, KioskView.checkedIn);
        expect(cubit.state.glanceLoading, isFalse);
        expect(cubit.state.pointsBalance, 2150);
        // Sorted cheapest-first (fixtures were pricey-first).
        expect(
          cubit.state.rewards.map((r) => r.rewardId).toList(),
          ['r-cheap', 'r-pricey'],
        );
      },
    );

    blocTest<KioskFlowCubit, KioskFlowState>(
      'degrades gracefully when the billing fetch fails — the glance still '
      'shows (streak + earned from the response), balance null',
      setUp: () {
        when(() => member.checkInMember(any()))
            .thenAnswer((_) async => recorded);
        when(() => member.getMemberDetail(any()))
            .thenThrow(Exception('billing down'));
      },
      build: build,
      act: (cubit) async {
        cubit.selectMember(member1);
        await cubit.selectClass(occ1);
        await Future<void>.delayed(const Duration(milliseconds: 20));
      },
      verify: (cubit) {
        expect(cubit.state.view, KioskView.checkedIn);
        expect(cubit.state.checkInResult?.classStreakWeeks, 3);
        expect(cubit.state.checkInResult?.pointsAwarded, 15);
        expect(cubit.state.glanceLoading, isFalse);
        expect(cubit.state.pointsBalance, isNull);
        // The catalog still loaded — only the balance fetch failed.
        expect(cubit.state.rewards, isNotEmpty);
      },
    );

    test('auto-returns home after the 8-second countdown (its own clock, '
        'not the 5-minute idle)', () {
      fakeAsync((async) {
        when(() => member.checkInMember(any()))
            .thenAnswer((_) async => recorded);
        final cubit = build();

        cubit.selectMember(member1);
        async.flushMicrotasks(); // class load settles
        cubit.selectClass(occ1);
        async.flushMicrotasks(); // check-in records + glance starts
        expect(cubit.state.view, KioskView.checkedIn);
        expect(cubit.state.glanceCountdown, kKioskGlanceAutoReturn.inSeconds);

        // Halfway the glance is still up (the 5-minute idle never fired).
        async.elapse(const Duration(seconds: 4));
        expect(cubit.state.view, KioskView.checkedIn);
        expect(cubit.state.idleWarningActive, isFalse);

        async.elapse(const Duration(seconds: 4)); // reaches 8s -> home
        expect(cubit.state.view, KioskView.home);
        expect(cubit.state.selectedMember, isNull);
        expect(cubit.state.glanceCountdown, 0);
        cubit.close();
      });
    });
  });
}
