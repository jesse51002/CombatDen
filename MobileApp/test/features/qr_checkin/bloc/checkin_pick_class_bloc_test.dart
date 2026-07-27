import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mobile_app/core/errors/exceptions.dart';
import 'package:mobile_app/core/state/selected_member.dart';
import 'package:mobile_app/features/home/data/models/class_occurrence.dart';
import 'package:mobile_app/features/home/data/repositories/member_classes_repository.dart';
import 'package:mobile_app/features/qr_checkin/bloc/checkin_pick_class_bloc.dart';
import 'package:mobile_app/features/qr_checkin/bloc/checkin_pick_class_event.dart';
import 'package:mobile_app/features/qr_checkin/bloc/checkin_pick_class_state.dart';

class _MockClassesRepo extends Mock implements MemberClassesRepository {}

ClassOccurrence _occ({
  String classId = 'c1',
  String time = '18:00:00',
  bool cancelled = false,
}) =>
    ClassOccurrence(
      classId: classId,
      gymId: 'g1',
      className: 'Muay Thai',
      classDate: '2026-07-23',
      originalDate: '2026-07-23',
      originalTime: time,
      occurredAt: '2026-07-23T${time}Z',
      resolvedClassTime: time,
      resolvedDurationMinutes: 55,
      resolvedInstructorName: 'Coach',
      imageUrl: 'https://x/i.png',
      pointsWorth: 50,
      isCancelled: cancelled,
      hasInstanceException: false,
      hasRangeException: false,
    );

void main() {
  late _MockClassesRepo classesRepo;

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
  });

  void stubBoard(List<ClassOccurrence> board) {
    when(() => classesRepo.getBoard(
          gymId: any(named: 'gymId'),
          memberId: any(named: 'memberId'),
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
        )).thenAnswer((_) async => board);
  }

  CheckinPickClassBloc build() =>
      CheckinPickClassBloc(classesRepository: classesRepo);

  blocTest<CheckinPickClassBloc, CheckinPickClassState>(
    'load returns today\'s classes, cancelled dropped, sorted soonest-first',
    setUp: () => stubBoard([
      _occ(classId: 'c-late', time: '19:00:00'),
      _occ(classId: 'c-cancelled', time: '17:00:00', cancelled: true),
      _occ(classId: 'c-early', time: '08:00:00'),
    ]),
    build: build,
    act: (b) => b.add(const CheckinPickClassLoadRequested()),
    expect: () => [
      isA<CheckinPickClassState>()
          .having((s) => s.status, 'status', CheckinPickClassStatus.loading),
      isA<CheckinPickClassState>()
          .having((s) => s.status, 'status', CheckinPickClassStatus.loaded)
          .having((s) => s.occurrences.length, 'count (cancelled dropped)', 2)
          .having(
            (s) => s.occurrences.first.classId,
            'soonest first',
            'c-early',
          )
          .having((s) => s.occurrences.last.classId, 'latest last', 'c-late'),
    ],
  );

  blocTest<CheckinPickClassBloc, CheckinPickClassState>(
    'no classes today → loaded empty (the empty state, not an error)',
    setUp: () => stubBoard(const []),
    build: build,
    act: (b) => b.add(const CheckinPickClassLoadRequested()),
    expect: () => [
      isA<CheckinPickClassState>()
          .having((s) => s.status, 'status', CheckinPickClassStatus.loading),
      isA<CheckinPickClassState>()
          .having((s) => s.status, 'status', CheckinPickClassStatus.loaded)
          .having((s) => s.occurrences, 'occurrences', isEmpty)
          .having((s) => s.isEmpty, 'isEmpty', true),
    ],
  );

  blocTest<CheckinPickClassBloc, CheckinPickClassState>(
    'a fetch failure is a retry-able error; a retry loads',
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
    },
    build: build,
    act: (b) async {
      b.add(const CheckinPickClassLoadRequested());
      await Future<void>.delayed(const Duration(milliseconds: 10));
      b.add(const CheckinPickClassLoadRequested());
    },
    expect: () => [
      isA<CheckinPickClassState>()
          .having((s) => s.status, 'status', CheckinPickClassStatus.loading),
      isA<CheckinPickClassState>()
          .having((s) => s.status, 'status', CheckinPickClassStatus.error)
          .having((s) => s.errorMessage, 'errorMessage', 'offline'),
      isA<CheckinPickClassState>()
          .having((s) => s.status, 'status', CheckinPickClassStatus.loading),
      isA<CheckinPickClassState>()
          .having((s) => s.status, 'status', CheckinPickClassStatus.loaded)
          .having((s) => s.occurrences.length, 'count', 1),
    ],
  );
}
