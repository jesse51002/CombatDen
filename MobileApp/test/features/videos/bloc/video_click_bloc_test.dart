import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mobile_app/core/errors/exceptions.dart';
import 'package:mobile_app/core/state/selected_member.dart';
import 'package:mobile_app/features/videos/bloc/video_click_bloc.dart';
import 'package:mobile_app/features/videos/bloc/video_click_bloc_state.dart';
import 'package:mobile_app/features/videos/bloc/video_click_event.dart';
import 'package:mobile_app/features/videos/data/repositories/member_videos_repository.dart';

class _MockVideosRepo extends Mock implements MemberVideosRepository {}

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

  tearDown(() async {
    await selectedMember.reset();
  });

  VideoClickBloc build() => VideoClickBloc(repository: repo);

  void stubOk() {
    when(() => repo.recordVideoClick(
          gymId: any(named: 'gymId'),
          memberId: any(named: 'memberId'),
          videoId: any(named: 'videoId'),
        )).thenAnswer((_) async {});
  }

  blocTest<VideoClickBloc, VideoClickBlocState>(
    'a feed open is reported for the selected member (no state change)',
    setUp: stubOk,
    build: build,
    act: (b) => b.add(const VideoOpenedFromFeed('v1')),
    expect: () => <VideoClickBlocState>[],
    verify: (_) {
      verify(() => repo.recordVideoClick(
            gymId: 'g1',
            memberId: 'm1',
            videoId: 'v1',
          )).called(1);
    },
  );

  blocTest<VideoClickBloc, VideoClickBlocState>(
    'the SAME video reported twice posts TWICE — append-only, never deduped',
    setUp: stubOk,
    build: build,
    act: (b) => b
      ..add(const VideoOpenedFromFeed('v1'))
      ..add(const VideoOpenedFromFeed('v1')),
    expect: () => <VideoClickBlocState>[],
    verify: (_) {
      verify(() => repo.recordVideoClick(
            gymId: 'g1',
            memberId: 'm1',
            videoId: 'v1',
          )).called(2);
    },
  );

  blocTest<VideoClickBloc, VideoClickBlocState>(
    'a report failure is swallowed — never throws, never emits',
    setUp: () {
      when(() => repo.recordVideoClick(
            gymId: any(named: 'gymId'),
            memberId: any(named: 'memberId'),
            videoId: any(named: 'videoId'),
          )).thenThrow(const NetworkException('offline'));
    },
    build: build,
    act: (b) => b.add(const VideoOpenedFromFeed('v1')),
    expect: () => <VideoClickBlocState>[],
    verify: (_) {
      verify(() => repo.recordVideoClick(
            gymId: 'g1',
            memberId: 'm1',
            videoId: 'v1',
          )).called(1);
    },
  );

  blocTest<VideoClickBloc, VideoClickBlocState>(
    'a blank video id is never reported',
    setUp: stubOk,
    build: build,
    act: (b) => b.add(const VideoOpenedFromFeed('   ')),
    expect: () => <VideoClickBlocState>[],
    verify: (_) {
      verifyNever(() => repo.recordVideoClick(
            gymId: any(named: 'gymId'),
            memberId: any(named: 'memberId'),
            videoId: any(named: 'videoId'),
          ));
    },
  );

  blocTest<VideoClickBloc, VideoClickBlocState>(
    'nothing is reported with no member selected',
    setUp: () async {
      stubOk();
      await selectedMember.reset();
    },
    build: build,
    act: (b) => b.add(const VideoOpenedFromFeed('v1')),
    expect: () => <VideoClickBlocState>[],
    verify: (_) {
      verifyNever(() => repo.recordVideoClick(
            gymId: any(named: 'gymId'),
            memberId: any(named: 'memberId'),
            videoId: any(named: 'videoId'),
          ));
    },
  );
}
