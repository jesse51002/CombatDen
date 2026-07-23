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
import 'package:crm/features/member_details/data/repositories/member_repository.dart';
import 'package:crm/features/members_list/data/models/crm_members_list_request.dart';
import 'package:crm/features/members_list/data/models/crm_members_list_response.dart';
import 'package:crm/features/members_list/data/models/member_row.dart';
import 'package:crm/features/members_list/data/models/members_list_filters.dart';
import 'package:crm/features/members_list/data/models/members_list_view.dart';
import 'package:crm/features/members_list/data/models/membership_status.dart';
import 'package:crm/features/members_list/data/repositories/members_list_repository.dart';
import 'package:crm/features/schedule/data/models/effective_class_instance.dart';
import 'package:crm/features/schedule/data/repositories/schedule_repository.dart';

class _MockMembersListRepository extends Mock
    implements MembersListRepository {}

class _MockScheduleRepository extends Mock implements ScheduleRepository {}

class _MockMemberRepository extends Mock implements MemberRepository {}

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

  late _MockMembersListRepository members;
  late _MockScheduleRepository schedule;
  late _MockMemberRepository member;
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
    session = _MockKioskSessionCubit();
    when(() => session.state).thenReturn(activeState);
    when(() => schedule.listEffectiveInstances(any(), any(), any()))
        .thenAnswer((_) async => <EffectiveClassInstance>[occ1]);
  });

  KioskFlowCubit build() => KioskFlowCubit(
        membersRepository: members,
        scheduleRepository: schedule,
        memberRepository: member,
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
      'a recorded check-in advances to the glance stub and ends the flow',
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
}
