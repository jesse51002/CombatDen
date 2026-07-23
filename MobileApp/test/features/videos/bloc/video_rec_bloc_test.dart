import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mobile_app/core/errors/exceptions.dart';
import 'package:mobile_app/core/state/selected_member.dart';
import 'package:mobile_app/features/videos/bloc/video_rec_bloc.dart';
import 'package:mobile_app/features/videos/bloc/video_rec_event.dart';
import 'package:mobile_app/features/videos/bloc/video_rec_state.dart';
import 'package:mobile_app/features/videos/data/models/gym_video_card.dart';
import 'package:mobile_app/features/videos/data/models/member_video_rec.dart';
import 'package:mobile_app/features/videos/data/models/video_genre.dart';
import 'package:mobile_app/features/videos/data/repositories/member_videos_repository.dart';

class _MockVideosRepo extends Mock implements MemberVideosRepository {}

GymVideoCard _card() => const GymVideoCard(
      videoId: 'v1',
      url: 'https://y/v1',
      title: 'Guard retention',
      thumbnailUrl: 'https://x/i.png',
      channelName: 'Channel',
      channelUrl: 'https://x/c',
      channelAvatarUrl: 'https://x/a.png',
      relevanceIndex: 0,
      tag: VideoGenre.educational,
      viewCount: 100,
    );

MemberVideoRec _rec() => MemberVideoRec(
      recId: 'rec1',
      category: VideoGenre.educational,
      video: _card(),
    );

void main() {
  late _MockVideosRepo repo;

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
    repo = _MockVideosRepo();
  });

  void stubRec(MemberVideoRec rec) {
    when(() => repo.fetchRec(
          gymId: any(named: 'gymId'),
          memberId: any(named: 'memberId'),
        )).thenAnswer((_) async => rec);
  }

  void stubClickOk() {
    when(() => repo.recordRecClick(
          gymId: any(named: 'gymId'),
          memberId: any(named: 'memberId'),
          recId: any(named: 'recId'),
        )).thenAnswer((_) async {});
  }

  VideoRecBloc build() => VideoRecBloc(repository: repo);

  blocTest<VideoRecBloc, VideoRecState>(
    'requesting the rec loads the served recommendation',
    setUp: () => stubRec(_rec()),
    build: build,
    act: (b) => b.add(const VideoRecRequested()),
    expect: () => [
      isA<VideoRecState>()
          .having((s) => s.status, 'status', VideoRecStatus.loading),
      isA<VideoRecState>()
          .having((s) => s.status, 'status', VideoRecStatus.loaded)
          .having((s) => s.rec?.recId, 'recId', 'rec1'),
    ],
  );

  blocTest<VideoRecBloc, VideoRecState>(
    'a 404 is a dismissible empty state, not an error',
    setUp: () {
      when(() => repo.fetchRec(
            gymId: any(named: 'gymId'),
            memberId: any(named: 'memberId'),
          )).thenThrow(
        const ServerException('Server error 404', statusCode: 404),
      );
    },
    build: build,
    act: (b) => b.add(const VideoRecRequested()),
    expect: () => [
      isA<VideoRecState>()
          .having((s) => s.status, 'status', VideoRecStatus.loading),
      isA<VideoRecState>()
          .having((s) => s.status, 'status', VideoRecStatus.empty),
    ],
  );

  blocTest<VideoRecBloc, VideoRecState>(
    'a non-404 failure surfaces a retryable error',
    setUp: () {
      when(() => repo.fetchRec(
            gymId: any(named: 'gymId'),
            memberId: any(named: 'memberId'),
          )).thenThrow(const NetworkException('offline'));
    },
    build: build,
    act: (b) => b.add(const VideoRecRequested()),
    expect: () => [
      isA<VideoRecState>()
          .having((s) => s.status, 'status', VideoRecStatus.loading),
      isA<VideoRecState>()
          .having((s) => s.status, 'status', VideoRecStatus.error)
          .having((s) => s.errorMessage, 'errorMessage', 'offline'),
    ],
  );

  blocTest<VideoRecBloc, VideoRecState>(
    'opening the rec records a click (no state change)',
    setUp: stubClickOk,
    build: build,
    seed: () => VideoRecState(status: VideoRecStatus.loaded, rec: _rec()),
    act: (b) => b.add(const VideoRecOpened()),
    expect: () => <VideoRecState>[],
    verify: (_) {
      verify(() => repo.recordRecClick(
            gymId: 'g1',
            memberId: 'm1',
            recId: 'rec1',
          )).called(1);
    },
  );

  blocTest<VideoRecBloc, VideoRecState>(
    'a click failure is swallowed — never breaks navigation, never emits',
    setUp: () {
      when(() => repo.recordRecClick(
            gymId: any(named: 'gymId'),
            memberId: any(named: 'memberId'),
            recId: any(named: 'recId'),
          )).thenThrow(const NetworkException('offline'));
    },
    build: build,
    seed: () => VideoRecState(status: VideoRecStatus.loaded, rec: _rec()),
    act: (b) => b.add(const VideoRecOpened()),
    expect: () => <VideoRecState>[],
    verify: (_) {
      verify(() => repo.recordRecClick(
            gymId: 'g1',
            memberId: 'm1',
            recId: 'rec1',
          )).called(1);
    },
  );

  blocTest<VideoRecBloc, VideoRecState>(
    'opening with no loaded rec does nothing (no click)',
    build: build,
    act: (b) => b.add(const VideoRecOpened()),
    expect: () => <VideoRecState>[],
    verify: (_) {
      verifyNever(() => repo.recordRecClick(
            gymId: any(named: 'gymId'),
            memberId: any(named: 'memberId'),
            recId: any(named: 'recId'),
          ));
    },
  );
}
