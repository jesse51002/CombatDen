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
import 'package:crm/features/member_details/data/models/rank.dart';
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
    when(() => detail.rank).thenReturn(
      const Rank(
        rankId: 'rank-blue',
        name: 'Blue',
        classesToNextMajor: 25,
        classesTillNextStep: 25,
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

        async.elapse(kKioskGlanceRevealSettle); // the reveal plays out

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

    test('the 8-second dwell starts AFTER the reveal settles, not on entry — '
        'the member gets the full eight seconds to read', () {
      // The bug this guards: starting the countdown on screen entry lets the
      // ~1s reveal choreography eat the dwell, leaving under 7 seconds to
      // actually read the streak. The full value is on screen from the first
      // frame (the footer never shows a drained "0s" mid-reveal); only the
      // DECREMENT waits.
      fakeAsync((async) {
        when(() => member.checkInMember(any()))
            .thenAnswer((_) async => recorded);
        final cubit = build();

        cubit.selectMember(member1);
        async.flushMicrotasks();
        cubit.selectClass(occ1);
        async.flushMicrotasks();
        expect(cubit.state.glanceCountdown, kKioskGlanceAutoReturn.inSeconds);

        // Through the whole reveal window the countdown has NOT moved.
        async.elapse(kKioskGlanceRevealSettle);
        expect(cubit.state.glanceCountdown, kKioskGlanceAutoReturn.inSeconds);

        // The first tick lands one second AFTER the settle, not one second
        // after entry.
        async.elapse(const Duration(seconds: 1));
        expect(
          cubit.state.glanceCountdown,
          kKioskGlanceAutoReturn.inSeconds - 1,
        );

        // A full eight seconds of dwell measured from the settle, no sooner:
        // at settle + 7s the glance is still up with a second to go.
        async.elapse(const Duration(seconds: 6));
        expect(cubit.state.view, KioskView.checkedIn);
        expect(cubit.state.glanceCountdown, 1);

        async.elapse(const Duration(seconds: 1)); // settle + 8s -> home
        expect(cubit.state.view, KioskView.home);
        cubit.close();
      });
    });

    test('leaving the glance during the reveal cancels the pending dwell — no '
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

        // The settle timer never promotes itself into a periodic countdown.
        async.elapse(const Duration(minutes: 1));
        expect(cubit.state.view, KioskView.home);
        expect(cubit.state.glanceCountdown, 0);
        cubit.close();
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
    test('opening the modal PAUSES the glance auto-return; its own 60s clock '
        'returns home', () {
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

        cubit.openAppModal();
        expect(cubit.state.appModalOpen, isTrue);
        expect(cubit.state.appModalCountdown, kKioskAppModalTimeout.inSeconds);
        expect(cubit.state.view, KioskView.checkedIn); // glance still behind it

        // The glance's 8s auto-return is paused — elapsing past it stays put.
        async.elapse(const Duration(seconds: 8));
        expect(cubit.state.view, KioskView.checkedIn);
        expect(cubit.state.appModalOpen, isTrue);

        // The modal's OWN 60s clock reaches zero and returns to a fresh home.
        async.elapse(const Duration(seconds: 52)); // total 60s
        expect(cubit.state.view, KioskView.home);
        expect(cubit.state.appModalOpen, isFalse);
        expect(cubit.state.selectedMember, isNull);
        cubit.close();
      });
    });

    test('Done closes the modal, returns home, and cancels the 60s timer', () {
      fakeAsync((async) {
        when(() => member.checkInMember(any()))
            .thenAnswer((_) async => recorded);
        final cubit = build();

        cubit.selectMember(member1);
        async.flushMicrotasks();
        cubit.selectClass(occ1);
        async.flushMicrotasks();
        cubit.openAppModal();
        expect(cubit.state.appModalOpen, isTrue);

        cubit.closeAppModal(); // Done
        expect(cubit.state.view, KioskView.home);
        expect(cubit.state.appModalOpen, isFalse);

        // The modal timer was cancelled — no late goHome, no pending-timer crash.
        async.elapse(const Duration(seconds: 120));
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
  });

  group('gym-wide showcase catalogues (fetched once at kiosk ENTRY)', () {
    test('warms rewards, this gym\'s own video feed, and the rank ladder — '
        'each exactly once, before any member arrives', () {
      fakeAsync((async) {
        final cubit = build();
        async.flushMicrotasks();

        // All three land on the IDLE HOME, so the "Get the app" modal opened
        // from the home QR panel already has them and fires no fetch.
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

    test('the glance also records the member\'s rank, for the "You\'re here" '
        'rung', () {
      fakeAsync((async) {
        when(() => member.checkInMember(any()))
            .thenAnswer((_) async => recorded);
        final cubit = build();

        cubit.selectMember(member1);
        async.flushMicrotasks();
        cubit.selectClass(occ1);
        async.flushMicrotasks();

        expect(cubit.state.view, KioskView.checkedIn);
        expect(cubit.state.currentRankId, 'rank-blue');

        // …and it is per-member, so it never follows the next person home.
        cubit.goHome();
        expect(cubit.state.currentRankId, isNull);
        cubit.close();
      });
    });
  });
}
