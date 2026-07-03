import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:crm/features/home/bloc/live_attendance_bloc.dart';
import 'package:crm/features/home/bloc/live_attendance_event.dart';
import 'package:crm/features/home/bloc/live_attendance_state.dart';
import 'package:crm/features/home/data/live_attendance_section.dart';
import 'package:crm/features/schedule/data/models/attendee_list_response.dart';
import 'package:crm/features/schedule/data/models/effective_class_instance.dart';
import 'package:crm/features/schedule/data/repositories/schedule_repository.dart';

class _MockScheduleRepository extends Mock implements ScheduleRepository {}

void main() {
  late _MockScheduleRepository repository;
  const gymId = 'gym-1';

  setUpAll(() {
    registerFallbackValue(DateTime(2000));
  });

  setUp(() {
    repository = _MockScheduleRepository();
  });

  EffectiveClassInstance instance(
    String classId,
    DateTime occurredAt, {
    int durationMinutes = 60,
    bool isCancelled = false,
  }) {
    final day =
        DateTime(occurredAt.year, occurredAt.month, occurredAt.day);
    return EffectiveClassInstance(
      classId: classId,
      gymId: gymId,
      className: 'Class $classId',
      classDate: day,
      originalDate: day,
      originalTime: '18:00:00',
      occurredAt: occurredAt,
      resolvedClassTime: '18:00:00',
      resolvedDurationMinutes: durationMinutes,
      pointsWorth: 10,
      isCancelled: isCancelled,
      hasInstanceException: false,
      hasRangeException: false,
    );
  }

  Attendee attendee(String id, {required bool attended}) => Attendee(
        memberId: id,
        fullName: 'Member $id',
        signedUp: true,
        attended: attended,
      );

  void stubInstances(List<EffectiveClassInstance> instances) {
    when(() => repository.listEffectiveInstances(any(), any(), any()))
        .thenAnswer((_) async => instances);
  }

  void stubRoster(List<Attendee> attendees) {
    when(() => repository.listAttendees(any(), any(), any(), any()))
        .thenAnswer(
      (inv) async => AttendeeListResponse(
        classId: inv.positionalArguments[1] as String,
        occurrenceDate: '2026-07-02',
        attendees: attendees,
      ),
    );
  }

  group('LiveAttendanceBloc', () {
    blocTest<LiveAttendanceBloc, LiveAttendanceState>(
      'shows the in-session occurrence with its roster (ended and '
      'far-future ones excluded)',
      setUp: () {
        final now = DateTime.now();
        stubInstances([
          instance('ended', now.subtract(const Duration(hours: 3))),
          instance('live', now.subtract(const Duration(minutes: 30))),
          instance('future', now.add(const Duration(hours: 5))),
        ]);
        stubRoster([
          attendee('a', attended: true),
          attendee('b', attended: false),
        ]);
      },
      build: () => LiveAttendanceBloc(repository: repository),
      act: (bloc) => bloc.add(const LiveAttendanceLoadRequested(gymId)),
      expect: () => [
        const LiveAttendanceLoading(),
        isA<LiveAttendanceLoaded>()
            .having((s) => s.isNextPreview, 'isNextPreview', false)
            .having((s) => s.sections.length, 'sections', 1)
            .having(
              (s) => s.sections.first.instance.classId,
              'shown class',
              'live',
            )
            .having((s) => s.checkedIn, 'checkedIn', 1)
            .having((s) => s.notArrived, 'notArrived', 1),
      ],
      verify: (_) {
        verify(() => repository.listAttendees(any(), 'live', any(), any()))
            .called(1);
        verifyNever(
          () => repository.listAttendees(any(), 'ended', any(), any()),
        );
      },
    );

    blocTest<LiveAttendanceBloc, LiveAttendanceState>(
      'falls forward to the soonest upcoming occurrence when nothing is '
      'live (skipping a cancelled sooner one)',
      setUp: () {
        final now = DateTime.now();
        stubInstances([
          instance('ended', now.subtract(const Duration(hours: 3))),
          instance(
            'cancelled',
            now.add(const Duration(hours: 1)),
            isCancelled: true,
          ),
          instance('next', now.add(const Duration(hours: 4))),
          instance('later', now.add(const Duration(days: 2))),
        ]);
        stubRoster([attendee('a', attended: false)]);
      },
      build: () => LiveAttendanceBloc(repository: repository),
      act: (bloc) => bloc.add(const LiveAttendanceLoadRequested(gymId)),
      expect: () => [
        const LiveAttendanceLoading(),
        isA<LiveAttendanceLoaded>()
            .having((s) => s.isNextPreview, 'isNextPreview', true)
            .having((s) => s.sections.length, 'sections', 1)
            .having(
              (s) => s.sections.first.instance.classId,
              'shown class',
              'next',
            ),
      ],
    );

    blocTest<LiveAttendanceBloc, LiveAttendanceState>(
      'previews BOTH occurrences when two classes start at the same '
      'upcoming instant',
      setUp: () {
        final start = DateTime.now().add(const Duration(hours: 4));
        stubInstances([instance('a', start), instance('b', start)]);
        stubRoster(const []);
      },
      build: () => LiveAttendanceBloc(repository: repository),
      act: (bloc) => bloc.add(const LiveAttendanceLoadRequested(gymId)),
      expect: () => [
        const LiveAttendanceLoading(),
        isA<LiveAttendanceLoaded>()
            .having((s) => s.isNextPreview, 'isNextPreview', true)
            .having((s) => s.sections.length, 'sections', 2),
      ],
    );

    blocTest<LiveAttendanceBloc, LiveAttendanceState>(
      'emits an empty preview (no roster reads) when nothing is scheduled',
      setUp: () => stubInstances([]),
      build: () => LiveAttendanceBloc(repository: repository),
      act: (bloc) => bloc.add(const LiveAttendanceLoadRequested(gymId)),
      expect: () => [
        const LiveAttendanceLoading(),
        const LiveAttendanceLoaded(sections: [], isNextPreview: true),
      ],
      verify: (_) {
        verifyNever(
          () => repository.listAttendees(any(), any(), any(), any()),
        );
      },
    );

    blocTest<LiveAttendanceBloc, LiveAttendanceState>(
      'emits error (with gymId for retry) when the load fails',
      setUp: () {
        when(() => repository.listEffectiveInstances(any(), any(), any()))
            .thenThrow(Exception('down'));
      },
      build: () => LiveAttendanceBloc(repository: repository),
      act: (bloc) => bloc.add(const LiveAttendanceLoadRequested(gymId)),
      expect: () => [
        const LiveAttendanceLoading(),
        isA<LiveAttendanceError>()
            .having((s) => s.gymId, 'gymId', gymId),
      ],
    );

    blocTest<LiveAttendanceBloc, LiveAttendanceState>(
      'refresh re-emits fresh data without an intermediate loading state',
      setUp: () {
        stubInstances([]);
      },
      build: () => LiveAttendanceBloc(repository: repository),
      act: (bloc) async {
        bloc.add(const LiveAttendanceLoadRequested(gymId));
        await Future<void>.delayed(Duration.zero);
        stubInstances(
          [instance('live', DateTime.now().subtract(
            const Duration(minutes: 10),
          ))],
        );
        stubRoster(const []);
        bloc.add(const LiveAttendanceRefreshRequested());
      },
      expect: () => [
        const LiveAttendanceLoading(),
        const LiveAttendanceLoaded(sections: [], isNextPreview: true),
        isA<LiveAttendanceLoaded>()
            .having((s) => s.isNextPreview, 'isNextPreview', false)
            .having((s) => s.sections, 'sections', [
          isA<LiveAttendanceSection>(),
        ]),
      ],
    );

    blocTest<LiveAttendanceBloc, LiveAttendanceState>(
      'a failed refresh keeps the last loaded data (no new state)',
      setUp: () {
        var calls = 0;
        when(() => repository.listEffectiveInstances(any(), any(), any()))
            .thenAnswer((_) async {
          calls++;
          if (calls > 1) throw Exception('blip');
          return <EffectiveClassInstance>[];
        });
      },
      build: () => LiveAttendanceBloc(repository: repository),
      act: (bloc) async {
        bloc.add(const LiveAttendanceLoadRequested(gymId));
        await Future<void>.delayed(Duration.zero);
        bloc.add(const LiveAttendanceRefreshRequested());
      },
      expect: () => [
        const LiveAttendanceLoading(),
        const LiveAttendanceLoaded(sections: [], isNextPreview: true),
      ],
    );

    blocTest<LiveAttendanceBloc, LiveAttendanceState>(
      'a refresh before any load is a no-op',
      build: () => LiveAttendanceBloc(repository: repository),
      act: (bloc) => bloc.add(const LiveAttendanceRefreshRequested()),
      expect: () => const <LiveAttendanceState>[],
    );
  });
}
