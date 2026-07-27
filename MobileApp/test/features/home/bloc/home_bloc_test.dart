import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mobile_app/core/errors/exceptions.dart';
import 'package:mobile_app/core/state/selected_member.dart';
import 'package:mobile_app/features/home/bloc/home_bloc.dart';
import 'package:mobile_app/features/home/bloc/home_event.dart';
import 'package:mobile_app/features/home/bloc/home_state.dart';
import 'package:mobile_app/features/home/data/models/class_history.dart';
import 'package:mobile_app/features/home/data/models/class_occurrence.dart';
import 'package:mobile_app/features/home/data/repositories/member_class_history_repository.dart';
import 'package:mobile_app/features/home/data/repositories/member_classes_repository.dart';

class _MockClassesRepo extends Mock implements MemberClassesRepository {}

class _MockHistoryRepo extends Mock implements MemberClassHistoryRepository {}

ClassOccurrence _occ({
  String classId = 'c1',
  String date = '2026-07-23',
  String time = '18:00:00',
  int signup = 5,
}) =>
    ClassOccurrence(
      classId: classId,
      gymId: 'g1',
      className: 'Muay Thai',
      classDate: date,
      originalDate: date,
      originalTime: time,
      occurredAt: '${date}T${time}Z',
      resolvedClassTime: time,
      resolvedDurationMinutes: 55,
      resolvedInstructorName: 'Coach',
      imageUrl: 'https://x/i.png',
      pointsWorth: 50,
      isCancelled: false,
      hasInstanceException: false,
      hasRangeException: false,
      signupCount: signup,
    );

MemberClassHistoryRow _row({
  String classId = 'c1',
  String date = '2026-07-23',
  String time = '18:00:00',
}) =>
    MemberClassHistoryRow(
      classId: classId,
      className: 'Muay Thai',
      imageUrl: 'https://x/i.png',
      originalDate: date,
      originalTime: time,
      durationMinutes: 55,
      status: MemberClassHistoryStatus.reserved,
    );

MemberClassHistory _history(List<MemberClassHistoryRow> upcoming) =>
    MemberClassHistory(upcoming: upcoming, history: const [], hasMore: false);

void main() {
  late _MockClassesRepo classesRepo;
  late _MockHistoryRepo historyRepo;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await selectedMember.select(
      memberId: 'm1',
      gymId: 'g1',
      gymName: 'Global MMA',
      firstName: 'Jane',
      lastName: 'Doe',
    );
    classesRepo = _MockClassesRepo();
    historyRepo = _MockHistoryRepo();
  });

  void stubBoard(List<ClassOccurrence> board) {
    when(() => classesRepo.getBoard(
          gymId: any(named: 'gymId'),
          memberId: any(named: 'memberId'),
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
        )).thenAnswer((_) async => board);
  }

  void stubHistory(MemberClassHistory history) {
    when(() => historyRepo.getHistory(
          gymId: any(named: 'gymId'),
          memberId: any(named: 'memberId'),
          limit: any(named: 'limit'),
          offset: any(named: 'offset'),
        )).thenAnswer((_) async => history);
  }

  HomeBloc build() => HomeBloc(
        classesRepository: classesRepo,
        historyRepository: historyRepo,
      );

  blocTest<HomeBloc, HomeState>(
    'load joins the board with reservations — booked flag + upcoming session',
    setUp: () {
      stubBoard([_occ()]);
      stubHistory(_history([_row()]));
    },
    build: build,
    act: (b) => b.add(const HomeLoadRequested()),
    expect: () => [
      isA<HomeState>().having((s) => s.status, 'status', HomeStatus.loading),
      isA<HomeState>()
          .having((s) => s.status, 'status', HomeStatus.loaded)
          .having((s) => s.occurrences.length, 'occurrences', 1)
          .having((s) => s.bookedKeys, 'bookedKeys', {'c1|2026-07-23|18:00:00'})
          .having((s) => s.upcoming.length, 'upcoming', 1),
    ],
  );

  blocTest<HomeBloc, HomeState>(
    'an occurrence with no matching reservation is NOT booked',
    setUp: () {
      stubBoard([_occ(classId: 'c1')]);
      // A reservation for a different class — should not mark c1 booked.
      stubHistory(_history([_row(classId: 'c2')]));
    },
    build: build,
    act: (b) => b.add(const HomeLoadRequested()),
    expect: () => [
      isA<HomeState>().having((s) => s.status, 'status', HomeStatus.loading),
      isA<HomeState>()
          .having((s) => s.status, 'status', HomeStatus.loaded)
          .having(
            (s) => s.bookedKeys.contains('c1|2026-07-23|18:00:00'),
            'c1 booked',
            false,
          ),
    ],
  );

  blocTest<HomeBloc, HomeState>(
    'a board failure surfaces a retry-able error; a retry loads',
    setUp: () {
      var call = 0;
      when(() => classesRepo.getBoard(
            gymId: any(named: 'gymId'),
            memberId: any(named: 'memberId'),
            startDate: any(named: 'startDate'),
            endDate: any(named: 'endDate'),
          )).thenAnswer((_) async {
        if (call++ == 0) throw const NetworkException('offline');
        return [_occ()];
      });
      stubHistory(_history(const []));
    },
    build: build,
    act: (b) async {
      b.add(const HomeLoadRequested());
      await Future<void>.delayed(const Duration(milliseconds: 10));
      b.add(const HomeLoadRequested());
    },
    expect: () => [
      isA<HomeState>().having((s) => s.status, 'status', HomeStatus.loading),
      isA<HomeState>()
          .having((s) => s.status, 'status', HomeStatus.error)
          .having((s) => s.errorMessage, 'errorMessage', 'offline'),
      isA<HomeState>().having((s) => s.status, 'status', HomeStatus.loading),
      isA<HomeState>()
          .having((s) => s.status, 'status', HomeStatus.loaded)
          .having((s) => s.occurrences.length, 'occurrences', 1),
    ],
  );
}
