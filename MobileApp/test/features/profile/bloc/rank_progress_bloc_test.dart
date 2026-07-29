import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mobile_app/core/errors/exceptions.dart';
import 'package:mobile_app/core/state/selected_member.dart';
import 'package:mobile_app/features/profile/bloc/rank_progress_bloc.dart';
import 'package:mobile_app/features/profile/bloc/rank_progress_event.dart';
import 'package:mobile_app/features/profile/bloc/rank_progress_state.dart';
import 'package:mobile_app/features/profile/data/models/member_rank_progress.dart';
import 'package:mobile_app/features/profile/data/models/rank_progress_point.dart';
import 'package:mobile_app/features/profile/data/repositories/member_rank_progress_repository.dart';

class _MockRankProgressRepo extends Mock
    implements MemberRankProgressRepository {}

MemberRankProgress _progress() => const MemberRankProgress(
      points: [
        RankProgressPoint(
          date: '2026-07-01',
          classesIntoRank: 0,
          classesNeeded: 10,
        ),
        RankProgressPoint(
          date: '2026-07-10',
          classesIntoRank: 4,
          classesNeeded: 10,
        ),
        RankProgressPoint(
          date: '2026-07-20',
          classesIntoRank: 7,
          classesNeeded: 10,
        ),
      ],
    );

void main() {
  late _MockRankProgressRepo repo;

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
    repo = _MockRankProgressRepo();
  });

  void stubProgress(MemberRankProgress progress) {
    when(() => repo.getRankProgress(
          gymId: any(named: 'gymId'),
          memberId: any(named: 'memberId'),
        )).thenAnswer((_) async => progress);
  }

  RankProgressBloc build() => RankProgressBloc(repository: repo);

  blocTest<RankProgressBloc, RankProgressState>(
    'load fetches the rank-progress series',
    setUp: () => stubProgress(_progress()),
    build: build,
    act: (b) => b.add(const RankProgressLoadRequested()),
    expect: () => [
      isA<RankProgressState>()
          .having((s) => s.status, 'status', RankProgressStatus.loading),
      isA<RankProgressState>()
          .having((s) => s.status, 'status', RankProgressStatus.loaded)
          .having((s) => s.points.length, 'points', 3),
    ],
  );

  blocTest<RankProgressBloc, RankProgressState>(
    'an empty series (no rank / ranks disabled) is a valid loaded state',
    setUp: () => stubProgress(const MemberRankProgress(points: [])),
    build: build,
    act: (b) => b.add(const RankProgressLoadRequested()),
    expect: () => [
      isA<RankProgressState>()
          .having((s) => s.status, 'status', RankProgressStatus.loading),
      isA<RankProgressState>()
          .having((s) => s.status, 'status', RankProgressStatus.loaded)
          .having((s) => s.points, 'points', isEmpty),
    ],
  );

  blocTest<RankProgressBloc, RankProgressState>(
    'a load failure surfaces a retry-able error',
    setUp: () {
      when(() => repo.getRankProgress(
            gymId: any(named: 'gymId'),
            memberId: any(named: 'memberId'),
          )).thenThrow(const NetworkException('offline'));
    },
    build: build,
    act: (b) => b.add(const RankProgressLoadRequested()),
    expect: () => [
      isA<RankProgressState>()
          .having((s) => s.status, 'status', RankProgressStatus.loading),
      isA<RankProgressState>()
          .having((s) => s.status, 'status', RankProgressStatus.error)
          .having((s) => s.errorMessage, 'errorMessage', 'offline'),
    ],
  );

  blocTest<RankProgressBloc, RankProgressState>(
    'retry after an error reloads the series and clears the error',
    setUp: () => stubProgress(_progress()),
    build: build,
    seed: () => const RankProgressState(
      status: RankProgressStatus.error,
      errorMessage: 'offline',
    ),
    act: (b) => b.add(const RankProgressLoadRequested()),
    expect: () => [
      isA<RankProgressState>()
          .having((s) => s.status, 'status', RankProgressStatus.loading)
          .having((s) => s.errorMessage, 'errorMessage', isNull),
      isA<RankProgressState>()
          .having((s) => s.status, 'status', RankProgressStatus.loaded)
          .having((s) => s.points.length, 'points', 3),
    ],
  );
}
