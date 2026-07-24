import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:crm/core/errors/exceptions.dart';
import 'package:crm/features/check_in/data/models/check_in_error_code.dart';
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
import 'package:crm/features/members/data/gym_content_repository.dart';
import 'package:crm/features/members/data/video_feed.dart';
import 'package:crm/features/members_list/data/models/crm_members_list_request.dart';
import 'package:crm/features/members_list/data/models/crm_members_list_response.dart';
import 'package:crm/features/members_list/data/models/member_row.dart';
import 'package:crm/features/members_list/data/models/members_list_filters.dart';
import 'package:crm/features/members_list/data/models/members_list_view.dart';
import 'package:crm/features/members_list/data/models/membership_status.dart';
import 'package:crm/features/members_list/data/repositories/members_list_repository.dart';
import 'package:crm/features/memberships/data/models/main_rank.dart';
import 'package:crm/features/memberships/data/models/rank_enabled_response.dart';
import 'package:crm/features/memberships/data/models/rank_ladder.dart';
import 'package:crm/features/memberships/data/models/rank_sub_type.dart';
import 'package:crm/features/memberships/data/repositories/ranks_repository.dart';
import 'package:crm/features/rewards/data/models/reward_response.dart';
import 'package:crm/features/rewards/data/repositories/rewards_repository.dart';
import 'package:crm/features/schedule/data/models/effective_class_instance.dart';
import 'package:crm/features/schedule/data/repositories/schedule_repository.dart';

class _MockMembersListRepository extends Mock
    implements MembersListRepository {}

class _MockScheduleRepository extends Mock implements ScheduleRepository {}

class _MockMemberRepository extends Mock implements MemberRepository {}

class _MockRewardsRepository extends Mock implements RewardsRepository {}

class _MockGymContentRepository extends Mock
    implements GymContentRepository {}

class _MockRanksRepository extends Mock implements RanksRepository {}

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

  final video1 = Video(
    url: 'https://youtube.com/watch?v=abc',
    title: 'Clinch control fundamentals',
    thumbnailUrl: 'https://img/1.jpg',
    channelName: 'Combat Culture',
    channelUrl: 'https://youtube.com/@cc',
    channelAvatarUrl: '',
    viewCount: 12000,
    relevanceIndex: 0,
    tags: const [],
    bigGroups: const [],
  );

  final blueRank = MainRank(
    rankId: 'rank-blue',
    gymId: gymId,
    mainRankNumOrder: 2,
    name: 'Blue',
    classesToNextMajor: 25,
    createdAt: t0,
  );

  late _MockMembersListRepository members;
  late _MockScheduleRepository schedule;
  late _MockMemberRepository member;
  late _MockRewardsRepository rewards;
  late _MockGymContentRepository content;
  late _MockRanksRepository ranks;
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
    content = _MockGymContentRepository();
    ranks = _MockRanksRepository();
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
    when(() => content.fetchVideos(any(),
            videoType: any(named: 'videoType'),
            rejected: any(named: 'rejected'),
            limit: any(named: 'limit'),
            offset: any(named: 'offset')))
        .thenAnswer((_) async => VideoPage(videos: [video1], total: 1));
    when(() => ranks.getRankEnabled(any())).thenAnswer(
      (_) async => const RankEnabledResponse(
        gymId: gymId,
        isRankEnabled: true,
      ),
    );
    when(() => ranks.listRanks(any())).thenAnswer(
      (_) async => RankLadder(
        ranks: [blueRank],
        subRankType: RankSubType.none,
      ),
    );
  });

  KioskFlowCubit build() => KioskFlowCubit(
        membersRepository: members,
        scheduleRepository: schedule,
        memberRepository: member,
        rewardsRepository: rewards,
        gymContentRepository: content,
        ranksRepository: ranks,
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
        classDate: DateTime(
          occurredAt.year,
          occurredAt.month,
          occurredAt.day,
        ),
        originalDate: DateTime(
          occurredAt.year,
          occurredAt.month,
          occurredAt.day,
        ),
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
      // Asserted on the settled state, not the emitted list: the three
      // gym-wide catalogues warmed at construction land asynchronously and
      // each publishes its own emit, so the stream carries entries this test
      // has no opinion about.
      verify: (cubit) {
        expect(cubit.state.view, KioskView.closing);
        verifyNever(() => session.beginFlow());
      },
    );
  });

  group('starting a signup (the same canStartFlow gate)', () {
    blocTest<KioskFlowCubit, KioskFlowState>(
      'startSignup opens the signup lane but does NOT begin the flow — the '
      'signup cubit owns that latch',
      build: build,
      act: (cubit) => cubit.startSignup(),
      verify: (cubit) {
        expect(cubit.state.view, KioskView.signup);
        // Double-counting here would leave the session permanently "busy" and
        // the kiosk would never sign itself out at its T+11h45 lockout.
        verifyNever(() => session.beginFlow());
      },
    );

    blocTest<KioskFlowCubit, KioskFlowState>(
      'startSignup shows the closing screen when the session cannot start '
      'a flow (locked)',
      setUp: () => when(() => session.state).thenReturn(lockedState),
      build: build,
      act: (cubit) => cubit.startSignup(),
      verify: (cubit) {
        expect(cubit.state.view, KioskView.closing);
        verifyNever(() => session.beginFlow());
      },
    );

    test('the signup view suppresses the check-in lane\'s idle guard — the '
        'signup lane runs its own', () {
      fakeAsync((async) {
        final cubit = build();
        cubit.startSignup();
        async.elapse(kKioskIdleTimeout + const Duration(seconds: 1));

        // Two guards over one surface would race: this one would abandon to
        // home mid-signup without releasing the signup's flow count.
        expect(cubit.state.view, KioskView.signup);
        expect(cubit.state.idleWarningActive, isFalse);
        cubit.close();
      });
    });
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
        // The picked class's NAME rides along — the response carries only a
        // class_id, and the glance has to confirm WHICH class it was.
        expect(cubit.state.selectedClassName, 'Muay Thai Fundamentals');
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

  group('rejection code off a thrown check-in error', () {
    // The backend emits a stable machine-readable `code` as a SIBLING of the
    // prose `detail` (`checkin_exceptions.py`). The kiosk carries the CODE —
    // never the prose, which is free to be reworded — so the blocked screen
    // can name a real reason. Anything unusable parses to null and the screen
    // keeps its generic line.
    Future<KioskFlowCubit> failWith(Object error) async {
      when(() => member.checkInMember(any())).thenThrow(error);
      final cubit = build();
      cubit.selectMember(member1);
      await Future<void>.delayed(Duration.zero); // class load settles
      await cubit.selectClass(occ1);
      addTearDown(cubit.close);
      return cubit;
    }

    ServerException rejection(Map<String, dynamic>? body) => ServerException(
          'Server error 400: Bad Request',
          statusCode: 400,
          detail: body?['detail'] as String?,
          data: body,
        );

    test('parses every backend code onto the state', () async {
      // The full CheckinErrorCode table, wire value -> enum member.
      const table = {
        'class_not_found': CheckInErrorCode.classNotFound,
        'class_deleted': CheckInErrorCode.classDeleted,
        'class_inactive': CheckInErrorCode.classInactive,
        'occurrence_not_found': CheckInErrorCode.occurrenceNotFound,
        'occurrence_cancelled': CheckInErrorCode.occurrenceCancelled,
        'checkin_not_open': CheckInErrorCode.checkinNotOpen,
        'class_full': CheckInErrorCode.classFull,
      };
      for (final entry in table.entries) {
        final cubit = await failWith(
          rejection({'detail': 'some prose', 'code': entry.key}),
        );
        expect(cubit.state.view, KioskView.blocked);
        expect(cubit.state.checkInFailed, isTrue);
        expect(cubit.state.checkInErrorCode, entry.value, reason: entry.key);
      }
    });

    test('a code this client does not know parses to unknown, not a crash',
        () async {
      final cubit = await failWith(
        rejection({'detail': 'brand new rule', 'code': 'gym_closed_today'}),
      );
      expect(cubit.state.checkInErrorCode, CheckInErrorCode.unknown);
    });

    test('an absent / null / non-String code leaves it null', () async {
      final absent = await failWith(rejection({'detail': 'Class is full'}));
      expect(absent.state.checkInErrorCode, isNull);

      final nulled = await failWith(
        rejection({'detail': 'Class is full', 'code': null}),
      );
      expect(nulled.state.checkInErrorCode, isNull);

      final nonString = await failWith(
        rejection({'detail': 'Class is full', 'code': 400}),
      );
      expect(nonString.state.checkInErrorCode, isNull);

      final noBody = await failWith(rejection(null));
      expect(noBody.state.checkInErrorCode, isNull);
    });

    test('a non-ServerException failure (network) carries no code', () async {
      final cubit = await failWith(
        const NetworkException('Network error: connection refused'),
      );
      expect(cubit.state.view, KioskView.blocked);
      expect(cubit.state.checkInFailed, isTrue);
      expect(cubit.state.checkInErrorCode, isNull);
    });

    test('a fresh failure with no code clears the previous member\'s code',
        () async {
      final cubit = await failWith(
        rejection({'detail': 'Class is full', 'code': 'class_full'}),
      );
      expect(cubit.state.checkInErrorCode, CheckInErrorCode.classFull);

      // Same cubit, a second attempt that fails with NO code: the stale reason
      // must not survive onto the new blocked screen. (`copyWith` keeps a
      // nullable outcome field by default — the catch passes null explicitly
      // for exactly this reason.)
      when(() => member.checkInMember(any()))
          .thenThrow(const NetworkException('Network error'));
      cubit.selectMember(member1);
      await Future<void>.delayed(Duration.zero);
      await cubit.selectClass(occ1);
      expect(cubit.state.checkInErrorCode, isNull);
    });
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

    test('auto-returns home after the 10-second hold (its own clock, '
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
        expect(cubit.state.glanceCountdown, kKioskGlanceHold.inSeconds);

        async.elapse(kKioskGlanceLastBeat); // the reveal plays out

        // Halfway the glance is still up (the 5-minute idle never fired).
        async.elapse(const Duration(seconds: 5));
        expect(cubit.state.view, KioskView.checkedIn);
        expect(cubit.state.idleWarningActive, isFalse);

        async.elapse(const Duration(seconds: 5)); // reaches 10s -> home
        expect(cubit.state.view, KioskView.home);
        expect(cubit.state.selectedMember, isNull);
        expect(cubit.state.glanceCountdown, 0);
        cubit.close();
      });
    });

    test('the 10-second hold starts AFTER the LAST beat, not on entry — the '
        'member gets the full ten seconds on a finished screen', () {
      // The bug this guards: starting the countdown on screen entry lets the
      // reveal choreography eat the hold — and the choreography is now 6.7s
      // long, so a member would be left barely three seconds of finished
      // screen. The full value is on screen from the first frame (the footer
      // never shows a drained "0s" mid-reveal); only the DECREMENT waits.
      fakeAsync((async) {
        when(() => member.checkInMember(any()))
            .thenAnswer((_) async => recorded);
        final cubit = build();

        cubit.selectMember(member1);
        async.flushMicrotasks();
        cubit.selectClass(occ1);
        async.flushMicrotasks();
        expect(cubit.state.glanceCountdown, kKioskGlanceHold.inSeconds);

        // Through the whole reveal window the countdown has NOT moved.
        async.elapse(kKioskGlanceLastBeat);
        expect(cubit.state.glanceCountdown, kKioskGlanceHold.inSeconds);

        // The first tick lands one second AFTER the last beat, not one second
        // after entry.
        async.elapse(const Duration(seconds: 1));
        expect(
          cubit.state.glanceCountdown,
          kKioskGlanceHold.inSeconds - 1,
        );

        // A full ten seconds of hold measured from the last beat, no sooner:
        // at lastBeat + 9s the glance is still up with a second to go.
        async.elapse(const Duration(seconds: 8));
        expect(cubit.state.view, KioskView.checkedIn);
        expect(cubit.state.glanceCountdown, 1);

        async.elapse(const Duration(seconds: 1)); // lastBeat + 10s -> home
        expect(cubit.state.view, KioskView.home);
        cubit.close();
      });
    });

    test('the glance lives for the reveal PLUS the hold, and every second of '
        'the hold is on a screen that has stopped moving', () {
      // The founder's shape: ~0s confirmation (centred) -> 3s lift + streak ->
      // 6.7s rewards -> +10s hold -> home. Nothing may return home early, and
      // nothing may hold the member past that.
      fakeAsync((async) {
        when(() => member.checkInMember(any()))
            .thenAnswer((_) async => recorded);
        final cubit = build();

        cubit.selectMember(member1);
        async.flushMicrotasks();
        cubit.selectClass(occ1);
        async.flushMicrotasks();

        // One tick short of the whole life: still up.
        async.elapse(
          kKioskGlanceLastBeat + kKioskGlanceHold - const Duration(seconds: 1),
        );
        expect(cubit.state.view, KioskView.checkedIn);

        async.elapse(const Duration(seconds: 1));
        expect(cubit.state.view, KioskView.home);
        cubit.close();
      });
    });

    test('leaving the glance during the reveal cancels the pending hold — no '
        'late auto-return over the next member', () {
      fakeAsync((async) {
        when(() => member.checkInMember(any()))
            .thenAnswer((_) async => recorded);
        final cubit = build();

        cubit.selectMember(member1);
        async.flushMicrotasks();
        cubit.selectClass(occ1);
        async.flushMicrotasks();

        cubit.goHome(); // Done, tapped mid-reveal
        expect(cubit.state.view, KioskView.home);

        // The pre-hold timer never promotes itself into a periodic countdown.
        async.elapse(const Duration(minutes: 1));
        expect(cubit.state.view, KioskView.home);
        expect(cubit.state.glanceCountdown, 0);
        cubit.close();
      });
    });

    test('Done during the CENTRED HOLD leaves immediately and cancels the '
        'pending auto-return', () {
      // The member must never be held hostage by the choreography: the first
      // three seconds are the longest stretch where nothing but the
      // confirmation is on screen, and Done has to work through all of it.
      fakeAsync((async) {
        when(() => member.checkInMember(any()))
            .thenAnswer((_) async => recorded);
        final cubit = build();

        cubit.selectMember(member1);
        async.flushMicrotasks();
        cubit.selectClass(occ1);
        async.flushMicrotasks();

        // One second in — the confirmation is still centred and alone.
        async.elapse(const Duration(seconds: 1));
        expect(cubit.state.view, KioskView.checkedIn);

        cubit.goHome();
        expect(cubit.state.view, KioskView.home);
        async.elapse(const Duration(minutes: 1));
        expect(cubit.state.view, KioskView.home);
        expect(cubit.state.glanceCountdown, 0);
        cubit.close();
      });
    });

    test('closing the cubit mid-reveal kills the pending auto-return', () {
      // close() cancels _glanceTimer in EITHER phase. A leaked pre-hold timer
      // would fire goHome() on a closed cubit (an emit-after-close throw) once
      // the reveal window elapsed.
      fakeAsync((async) {
        when(() => member.checkInMember(any()))
            .thenAnswer((_) async => recorded);
        final cubit = build();

        cubit.selectMember(member1);
        async.flushMicrotasks();
        cubit.selectClass(occ1);
        async.flushMicrotasks();

        cubit.close();
        // Past the last beat AND the whole hold: nothing fires, nothing throws.
        async.elapse(kKioskGlanceLastBeat + kKioskGlanceHold);
        expect(async.pendingTimers, isEmpty);
      });
    });
  });

  group('the class-pick escape ("Not Marcus?")', () {
    // The founder-reported gap: a member taps the WRONG name on home, lands on
    // class pick, and without an escape is stranded until the 5-minute idle
    // guard fires. The escape button is wired to goHome() — which is already
    // the whole abandon contract — and these prove it stays that way.
    blocTest<KioskFlowCubit, KioskFlowState>(
      'returns to a clean home and BALANCES beginFlow/endFlow',
      build: build,
      act: (cubit) async {
        cubit.selectMember(member1); // beginFlow
        await Future<void>.delayed(Duration.zero); // class load settles
        cubit.goHome(); // the escape
      },
      verify: (cubit) {
        expect(cubit.state.view, KioskView.home);
        // Exactly one end per begin. An escape that skipped endFlow would leak
        // the session's in-progress flow count permanently, and the kiosk
        // would then never sign itself out at the T+11h45 lockout.
        verify(() => session.beginFlow()).called(1);
        verify(() => session.endFlow()).called(1);
      },
    );

    blocTest<KioskFlowCubit, KioskFlowState>(
      'leaves NO trace of the mis-tapped member on the shared iPad',
      build: build,
      act: (cubit) async {
        cubit.search('mar');
        cubit.selectMember(member1);
        await Future<void>.delayed(Duration.zero);
        cubit.goHome();
      },
      verify: (cubit) {
        // The same privacy rule the idle guard enforces: no name, no query, no
        // results, no picked class may survive on a shared lobby kiosk.
        expect(cubit.state.selectedMember, isNull);
        expect(cubit.state.searchQuery, isEmpty);
        expect(cubit.state.searchResults, isEmpty);
        expect(cubit.state.selectedClassName, isNull);
        expect(cubit.state.classes, isEmpty);
      },
    );

    test('a second escape does not double-end the flow', () {
      // _flowStarted is the latch; a double tap on the escape (or an escape
      // then an idle timeout) must not decrement the session's count twice.
      fakeAsync((async) {
        final cubit = build();
        cubit.selectMember(member1);
        async.flushMicrotasks();
        cubit.goHome();
        cubit.goHome();
        verify(() => session.beginFlow()).called(1);
        verify(() => session.endFlow()).called(1);
        cubit.close();
      });
    });
  });

  group('get-the-app modal (UX-5)', () {
    test('opening the modal DURING THE REVEAL pauses the pending auto-return; '
        'its own 60s clock returns home', () {
      // The tap lands while the confirmation is still centred — the pre-hold
      // phase of _glanceTimer. Cancelling there must stop the auto-return
      // dead, not merely postpone the periodic that phase would have started.
      fakeAsync((async) {
        when(() => member.checkInMember(any()))
            .thenAnswer((_) async => recorded);
        final cubit = build();

        cubit.selectMember(member1);
        async.flushMicrotasks(); // class load settles
        cubit.selectClass(occ1);
        async.flushMicrotasks(); // check-in records + glance starts
        expect(cubit.state.view, KioskView.checkedIn);
        expect(cubit.state.glanceCountdown, kKioskGlanceHold.inSeconds);

        cubit.openAppModal();
        expect(cubit.state.appModalOpen, isTrue);
        expect(cubit.state.appModalCountdown, kKioskAppModalTimeout.inSeconds);
        expect(cubit.state.view, KioskView.checkedIn); // glance still behind it

        // Past the point the glance would have gone home on its own — it
        // stays put behind the modal.
        async.elapse(const Duration(seconds: 30));
        expect(cubit.state.view, KioskView.checkedIn);
        expect(cubit.state.appModalOpen, isTrue);

        // The modal's OWN 60s clock reaches zero and returns to a fresh home.
        async.elapse(const Duration(seconds: 30)); // total 60s
        expect(cubit.state.view, KioskView.home);
        expect(cubit.state.appModalOpen, isFalse);
        expect(cubit.state.selectedMember, isNull);
        cubit.close();
      });
    });

    test('opening the modal DURING THE HOLD pauses the running countdown', () {
      // The other phase of the same timer: the per-second countdown is already
      // draining. Cancelling it must freeze the glance behind the modal.
      fakeAsync((async) {
        when(() => member.checkInMember(any()))
            .thenAnswer((_) async => recorded);
        final cubit = build();

        cubit.selectMember(member1);
        async.flushMicrotasks();
        cubit.selectClass(occ1);
        async.flushMicrotasks();

        // Into the hold: the countdown has started draining.
        async.elapse(kKioskGlanceLastBeat + const Duration(seconds: 3));
        expect(cubit.state.glanceCountdown, kKioskGlanceHold.inSeconds - 3);

        cubit.openAppModal();
        // The remaining seven seconds never tick down.
        async.elapse(const Duration(seconds: 20));
        expect(cubit.state.view, KioskView.checkedIn);
        expect(cubit.state.glanceCountdown, kKioskGlanceHold.inSeconds - 3);
        cubit.close();
      });
    });

    test('Done returns to the GLANCE it opened over, not home, and gives the '
        'member the WHOLE hold back', () {
      // The founder-reported bug: Done ejected the member out of their own
      // check-in result. The modal is an overlay, so closing it must reveal
      // what was underneath — and because the member spent their reading time
      // inside the modal, the ten seconds start again from full rather than
      // handing back the few that were left.
      fakeAsync((async) {
        when(() => member.checkInMember(any()))
            .thenAnswer((_) async => recorded);
        final cubit = build();

        cubit.selectMember(member1);
        async.flushMicrotasks();
        cubit.selectClass(occ1);
        async.flushMicrotasks();

        // Burn most of the hold, then open the modal over it.
        async.elapse(kKioskGlanceLastBeat + const Duration(seconds: 8));
        expect(cubit.state.glanceCountdown, kKioskGlanceHold.inSeconds - 8);
        cubit.openAppModal();

        cubit.closeAppModal(); // Done
        expect(cubit.state.view, KioskView.checkedIn);
        expect(cubit.state.appModalOpen, isFalse);
        expect(cubit.state.appModalCountdown, 0);
        // The member's own result is still there — nothing was abandoned.
        expect(cubit.state.selectedMember, member1);
        expect(cubit.state.checkInResult, recorded);
        // Reset to FULL, not the two seconds that were left.
        expect(cubit.state.glanceCountdown, kKioskGlanceHold.inSeconds);

        // And the restarted hold drains immediately — it does NOT wait out the
        // reveal's last beat a second time (the glance is already settled).
        async.elapse(const Duration(seconds: 1));
        expect(cubit.state.glanceCountdown, kKioskGlanceHold.inSeconds - 1);

        // Ten full seconds from Done, then home on the glance's own clock.
        async.elapse(const Duration(seconds: 8));
        expect(cubit.state.view, KioskView.checkedIn);
        async.elapse(const Duration(seconds: 1));
        expect(cubit.state.view, KioskView.home);
        cubit.close();
      });
    });

    test('Done from the HOME returns to the home it opened over', () {
      fakeAsync((async) {
        final cubit = build();
        cubit.openAppModal();
        expect(cubit.state.appModalOpen, isTrue);

        cubit.closeAppModal(); // Done
        expect(cubit.state.view, KioskView.home);
        expect(cubit.state.appModalOpen, isFalse);
        cubit.close();
      });
    });

    test('Done cancels the modal\'s own 60s timer', () {
      // A surviving timer would fire a goHome long after the member had moved
      // on — off the glance they were handed back to, or over the next
      // person's flow.
      fakeAsync((async) {
        when(() => member.checkInMember(any()))
            .thenAnswer((_) async => recorded);
        final cubit = build();

        cubit.selectMember(member1);
        async.flushMicrotasks();
        cubit.selectClass(occ1);
        async.flushMicrotasks();
        cubit.openAppModal();
        cubit.closeAppModal();

        // The glance's own 10s hold takes it home; nothing at the 60s mark
        // re-fires, and no pending-timer crash.
        async.elapse(const Duration(seconds: 120));
        expect(cubit.state.view, KioskView.home);
        expect(cubit.state.appModalOpen, isFalse);
        cubit.close();
      });
    });

    test('EXPIRY goes home even off the glance — nobody is standing there', () {
      // The deliberate split from Done: sixty seconds of no interaction means
      // the member walked away, and leaving their name + streak up on a shared
      // iPad for the next person is the wrong default.
      fakeAsync((async) {
        when(() => member.checkInMember(any()))
            .thenAnswer((_) async => recorded);
        final cubit = build();

        cubit.selectMember(member1);
        async.flushMicrotasks();
        cubit.selectClass(occ1);
        async.flushMicrotasks();
        cubit.openAppModal();

        async.elapse(kKioskAppModalTimeout);
        expect(cubit.state.view, KioskView.home);
        expect(cubit.state.appModalOpen, isFalse);
        expect(cubit.state.selectedMember, isNull);
        expect(cubit.state.checkInResult, isNull);
        cubit.close();
      });
    });

    test('closing a modal that is not open is a no-op', () {
      fakeAsync((async) {
        final cubit = build();
        cubit.closeAppModal();
        expect(cubit.state.appModalOpen, isFalse);
        expect(cubit.state.view, KioskView.home);
        cubit.close();
      });
    });

    test('opening the modal from home is informational — it begins NO member '
        'flow', () {
      final cubit = build();
      cubit.openAppModal();
      expect(cubit.state.appModalOpen, isTrue);
      expect(cubit.state.view, KioskView.home);
      verifyNever(() => session.beginFlow());
      cubit.close();
    });

    test('opening the modal fires NO network call — every slide input is '
        'already in memory', () {
      // The modal must open instantly on a supervised iPad, so it is fed
      // entirely from the catalogues warmed at entry. A per-open fetch would
      // put a spinner (or a blank slide) in front of a member.
      fakeAsync((async) {
        final cubit = build();
        async.flushMicrotasks(); // the entry warms all land
        clearInteractions(schedule);
        clearInteractions(rewards);
        clearInteractions(content);
        clearInteractions(ranks);
        clearInteractions(member);
        clearInteractions(members);

        cubit.openAppModal();
        async.flushMicrotasks();
        expect(cubit.state.appModalOpen, isTrue);

        verifyZeroInteractions(schedule);
        verifyZeroInteractions(rewards);
        verifyZeroInteractions(content);
        verifyZeroInteractions(ranks);
        verifyZeroInteractions(member);
        verifyZeroInteractions(members);
        cubit.close();
      });
    });
  });

  group('the showcase\'s OWN class list (warmed at kiosk ENTRY)', () {
    // Fixed now = t0 = 2026-01-01 18:00. TWO class lists exist on purpose:
    //  · the CHECK-IN flow's — today only, narrowed to the check-in window,
    //    read per member (it must never offer an unbookable class);
    //  · the SHOWCASE's — a week-wide FORWARD window, read once at entry (it
    //    must not empty itself at 9pm, which is how the founder's "only 3
    //    slides" bug would come back at a different hour).
    // Collapsing them into one list re-introduces one bug or the other.
    final showcaseStart = DateTime(2026, 1, 1);
    final showcaseEnd = DateTime(2026, 1, 1 + kKioskShowcaseClassDays);

    // 19:00 tonight: upcoming AND inside the 2h check-in window.
    final soon = occAt('soon', t0.add(const Duration(hours: 1)));
    // Tomorrow evening: upcoming, but far outside the check-in window — it can
    // only ever reach the SHOWCASE.
    final tomorrow = occAt('tomorrow', t0.add(const Duration(days: 1)));
    // Finished two hours ago: never bookable, never shown.
    final ended = occAt('ended', t0.subtract(const Duration(hours: 2)));
    final cancelled = occAt(
      'cancelled',
      t0.add(const Duration(hours: 2)),
      cancelled: true,
    );

    void stubShowcase(List<EffectiveClassInstance> board) {
      when(() => schedule.listEffectiveInstances(
          gymId, showcaseStart, showcaseEnd)).thenAnswer((_) async => board);
    }

    test('warms the gym\'s next upcoming classes at ENTRY, so the modal opened '
        'from the HOME has its "Book classes" slide', () {
      // The founder-reported bug: from the home QR panel the modal showed
      // "only 3 slides instead of 4", because nothing warmed classes and
      // `state.classes` is only filled once a member has been picked.
      fakeAsync((async) {
        stubShowcase([tomorrow, ended, soon, cancelled]);
        final cubit = build();
        async.flushMicrotasks();

        expect(cubit.state.view, KioskView.home);
        // Soonest first; the finished and cancelled ones are dropped — a Book
        // pill beside a class that already ended is not a real affordance.
        expect(
          cubit.state.showcaseClasses.map((c) => c.classId).toList(),
          ['soon', 'tomorrow'],
        );
        // ONE call, over the forward window — not a per-open fetch.
        verify(() => schedule.listEffectiveInstances(
            gymId, showcaseStart, showcaseEnd)).called(1);
        cubit.close();
      });
    });

    test('caps at kKioskShowcaseClassCount — the slide is a two-row list, not '
        'a schedule dump', () {
      fakeAsync((async) {
        stubShowcase([
          soon,
          tomorrow,
          occAt('day-3', t0.add(const Duration(days: 3))),
          occAt('day-5', t0.add(const Duration(days: 5))),
        ]);
        final cubit = build();
        async.flushMicrotasks();

        expect(
          cubit.state.showcaseClasses.length,
          kKioskShowcaseClassCount,
        );
        cubit.close();
      });
    });

    test('is INDEPENDENT of the check-in flow\'s filtered list — a class '
        'outside the check-in window still reaches the showcase, and never '
        'the class pick', () {
      fakeAsync((async) {
        stubShowcase([soon, tomorrow]);
        // The flow reads TODAY only, and its own filter still governs it.
        when(() => schedule.listEffectiveInstances(
                gymId, showcaseStart, showcaseStart))
            .thenAnswer((_) async => [occ1, tomorrow, ended]);
        final cubit = build();
        async.flushMicrotasks();

        cubit.selectMember(member1);
        async.flushMicrotasks();

        // The class pick offers ONLY what this member can check into right
        // now — tomorrow's class and the finished one are both dropped. This
        // filter is a live wrong-check-in guard; the showcase must never
        // loosen it.
        expect(
          cubit.state.classes.map((c) => c.classId).toList(),
          ['class-1'],
        );
        // And the showcase keeps looking forward, untouched by the flow.
        expect(
          cubit.state.showcaseClasses.map((c) => c.classId).toList(),
          ['soon', 'tomorrow'],
        );
        cubit.close();
      });
    });

    test('survives a return home — no re-fetch per member', () {
      fakeAsync((async) {
        stubShowcase([soon, tomorrow]);
        final cubit = build();
        async.flushMicrotasks();

        cubit.selectMember(member1); // the flow's own fetch runs
        async.flushMicrotasks();
        cubit.goHome();
        async.flushMicrotasks();

        expect(
          cubit.state.showcaseClasses.map((c) => c.classId).toList(),
          ['soon', 'tomorrow'],
        );
        // Still exactly one forward-window read — goHome re-seeds it from the
        // entry-time cache.
        verify(() => schedule.listEffectiveInstances(
            gymId, showcaseStart, showcaseEnd)).called(1);
        cubit.close();
      });
    });

    test('drops a cached class once it has STARTED — a kiosk runs for hours '
        'on one warm and must not advertise this morning\'s class tonight', () {
      // The staleness this guards: one warm covers a 12-hour session, so
      // without a prune a 7pm class would still sit under a Book pill at 10pm,
      // labelled "Today". No re-fetch — the cache just drains, and an empty
      // list omits the slide (the designed degradation).
      fakeAsync((async) {
        stubShowcase([soon, tomorrow]);
        var clock = t0;
        final cubit = KioskFlowCubit(
          membersRepository: members,
          scheduleRepository: schedule,
          memberRepository: member,
          rewardsRepository: rewards,
          gymContentRepository: content,
          ranksRepository: ranks,
          session: session,
          gymId: gymId,
          now: () => clock,
        );
        async.flushMicrotasks();
        expect(
          cubit.state.showcaseClasses.map((c) => c.classId).toList(),
          ['soon', 'tomorrow'],
        );

        clock = t0.add(const Duration(hours: 4)); // 19:00 has been and gone
        cubit.goHome();
        async.flushMicrotasks();

        expect(
          cubit.state.showcaseClasses.map((c) => c.classId).toList(),
          ['tomorrow'],
        );
        // Still exactly one read — pruning costs no network.
        verify(() => schedule.listEffectiveInstances(
            gymId, showcaseStart, showcaseEnd)).called(1);
        cubit.close();
      });
    });

    test('a gym that runs no classes still gets an EMPTY list — the slide and '
        'its dot stay omitted', () {
      fakeAsync((async) {
        stubShowcase(const []);
        final cubit = build();
        async.flushMicrotasks();

        expect(cubit.state.showcaseClasses, isEmpty);
        expect(cubit.state.view, KioskView.home);
        cubit.close();
      });
    });

    test('a failed fetch degrades to an omitted slide, never an error state',
        () {
      fakeAsync((async) {
        when(() => schedule.listEffectiveInstances(
            gymId, showcaseStart, showcaseEnd)).thenThrow(
          Exception('schedule down'),
        );
        final cubit = build();
        async.flushMicrotasks();

        expect(cubit.state.showcaseClasses, isEmpty);
        expect(cubit.state.view, KioskView.home);
        expect(cubit.state.classesFailed, isFalse); // not the flow's flag
        cubit.close();
      });
    });

    test('a failed showcase warm leaves the CHECK-IN flow working', () {
      // The two reads are independent: a broken forward window must not cost a
      // member their check-in.
      fakeAsync((async) {
        when(() => schedule.listEffectiveInstances(
            gymId, showcaseStart, showcaseEnd)).thenThrow(
          Exception('schedule down'),
        );
        when(() => schedule.listEffectiveInstances(
                gymId, showcaseStart, showcaseStart))
            .thenAnswer((_) async => [occ1]);
        final cubit = build();
        async.flushMicrotasks();

        cubit.selectMember(member1);
        async.flushMicrotasks();

        expect(cubit.state.classes.map((c) => c.classId).toList(),
            ['class-1']);
        expect(cubit.state.classesFailed, isFalse);
        cubit.close();
      });
    });
  });

  group('gym-wide showcase catalogues (fetched once at kiosk ENTRY)', () {
    test('warms rewards, this gym\'s own video feed, and the rank ladder — '
        'each exactly once, before any member arrives', () {
      fakeAsync((async) {
        final cubit = build();
        async.flushMicrotasks();

        // All three land on the IDLE HOME, so the "Get the app" modal opened
        // from the home adopt strip already has them and fires no fetch.
        expect(cubit.state.view, KioskView.home);
        expect(cubit.state.rewards, [rewardCheap, rewardPricey]);
        expect(cubit.state.videos, [video1]);
        expect(cubit.state.rankLadder, [blueRank]);

        // The gym's OWN feed, gym-id scoped — never the default content gym's
        // showcase that `selectedGym.detail` carries.
        verify(() => content.fetchVideos(gymId,
            videoType: any(named: 'videoType'),
            rejected: any(named: 'rejected'),
            limit: kKioskShowcaseVideoCount,
            offset: any(named: 'offset'))).called(1);
        verify(() => ranks.getRankEnabled(gymId)).called(1);
        verify(() => ranks.listRanks(gymId)).called(1);
        cubit.close();
      });
    });

    test('the catalogues survive a return home — no re-fetch per member', () {
      fakeAsync((async) {
        final cubit = build();
        async.flushMicrotasks();

        cubit.goHome();
        async.flushMicrotasks();

        expect(cubit.state.rewards, [rewardCheap, rewardPricey]);
        expect(cubit.state.videos, [video1]);
        expect(cubit.state.rankLadder, [blueRank]);
        // Still one call each — goHome re-seeds from the entry-time cache.
        verify(() => content.fetchVideos(any(),
            videoType: any(named: 'videoType'),
            rejected: any(named: 'rejected'),
            limit: any(named: 'limit'),
            offset: any(named: 'offset'))).called(1);
        verify(() => ranks.listRanks(any())).called(1);
        cubit.close();
      });
    });

    test('a gym with ranks switched OFF gets no ladder (and never reads it)',
        () {
      fakeAsync((async) {
        when(() => ranks.getRankEnabled(any())).thenAnswer(
          (_) async => const RankEnabledResponse(
            gymId: gymId,
            isRankEnabled: false,
          ),
        );
        final cubit = build();
        async.flushMicrotasks();

        expect(cubit.state.rankLadder, isEmpty);
        verifyNever(() => ranks.listRanks(any()));
        cubit.close();
      });
    });

    test('a failed catalogue fetch is non-fatal — it just leaves that list '
        'empty', () {
      fakeAsync((async) {
        when(() => content.fetchVideos(any(),
                videoType: any(named: 'videoType'),
                rejected: any(named: 'rejected'),
                limit: any(named: 'limit'),
                offset: any(named: 'offset')))
            .thenThrow(Exception('feed down'));
        when(() => ranks.getRankEnabled(any())).thenThrow(Exception('down'));
        final cubit = build();
        async.flushMicrotasks();

        // No error view, no thrown state — the slides are simply omitted.
        expect(cubit.state.view, KioskView.home);
        expect(cubit.state.videos, isEmpty);
        expect(cubit.state.rankLadder, isEmpty);
        cubit.close();
      });
    });

    test('a check-in leaves the rank showcase input untouched — that slide '
        'holds NO member link', () {
      fakeAsync((async) {
        when(() => member.checkInMember(any()))
            .thenAnswer((_) async => recorded);
        final cubit = build();
        async.flushMicrotasks();
        final ladderAtEntry = cubit.state.rankLadder;

        cubit.selectMember(member1);
        async.flushMicrotasks();
        cubit.selectClass(occ1);
        async.flushMicrotasks();

        // The glance's member fetch still lands — it pays for the points
        // balance — but nothing rank-shaped is taken off it. The "Track rank"
        // slide features a MIDDLE rung over an illustrative bar in every
        // state (see `KioskRankSlide`), so there is no per-member rank field
        // that could follow the next person home.
        expect(cubit.state.view, KioskView.checkedIn);
        expect(cubit.state.pointsBalance, 2150);
        expect(cubit.state.rankLadder, ladderAtEntry);
        expect(cubit.state.rankLadder, [blueRank]);
        cubit.close();
      });
    });
  });
}
