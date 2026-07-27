import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mobile_app/core/errors/exceptions.dart';
import 'package:mobile_app/core/state/selected_member.dart';
import 'package:mobile_app/features/videos/bloc/videos_bloc.dart';
import 'package:mobile_app/features/videos/bloc/videos_event.dart';
import 'package:mobile_app/features/videos/bloc/videos_state.dart';
import 'package:mobile_app/features/videos/data/models/gym_video_card.dart';
import 'package:mobile_app/features/videos/data/models/gym_videos_feed.dart';
import 'package:mobile_app/features/videos/data/models/video_genre.dart';
import 'package:mobile_app/features/videos/data/repositories/member_videos_repository.dart';

class _MockVideosRepo extends Mock implements MemberVideosRepository {}

GymVideoCard _card({String id = 'v1', VideoGenre? tag = VideoGenre.educational}) =>
    GymVideoCard(
      videoId: id,
      url: 'https://y/$id',
      title: 'Title $id',
      thumbnailUrl: 'https://x/i.png',
      channelName: 'Channel',
      channelUrl: 'https://x/c',
      channelAvatarUrl: 'https://x/a.png',
      relevanceIndex: 0,
      tag: tag,
      viewCount: 100,
    );

GymVideosFeed _feed(List<GymVideoCard> videos) =>
    GymVideosFeed(total: videos.length, limit: 50, offset: 0, videos: videos);

void main() {
  late _MockVideosRepo repo;

  setUpAll(() => registerFallbackValue(VideoGenre.educational));

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

  // fetchFeed answers by video_type: the "All" (null) call returns two genres,
  // a genre call returns just that genre.
  void stubFeed() {
    when(() => repo.fetchFeed(
          gymId: any(named: 'gymId'),
          memberId: any(named: 'memberId'),
          videoType: any(named: 'videoType'),
          limit: any(named: 'limit'),
          offset: any(named: 'offset'),
        )).thenAnswer((invocation) async {
      final vt = invocation.namedArguments[#videoType] as VideoGenre?;
      if (vt == null) {
        return _feed([
          _card(id: 'e1', tag: VideoGenre.educational),
          _card(id: 'x1', tag: VideoGenre.entertainment),
        ]);
      }
      return _feed([_card(id: '${vt.name}1', tag: vt)]);
    });
  }

  VideosBloc build() => VideosBloc(repository: repo);

  blocTest<VideosBloc, VideosState>(
    'load fetches the All feed and derives the genre tabs',
    setUp: stubFeed,
    build: build,
    act: (b) => b.add(const VideosLoadRequested()),
    expect: () => [
      isA<VideosState>()
          .having((s) => s.status, 'status', VideosStatus.loading),
      isA<VideosState>()
          .having((s) => s.status, 'status', VideosStatus.loaded)
          .having((s) => s.videos.length, 'videos', 2)
          .having((s) => s.selectedGenre, 'selectedGenre', isNull)
          .having(
            (s) => s.availableGenres,
            'availableGenres',
            [VideoGenre.educational, VideoGenre.entertainment],
          ),
    ],
  );

  blocTest<VideosBloc, VideosState>(
    'selecting a category reloads the feed via video_type and keeps the tabs',
    setUp: stubFeed,
    build: build,
    seed: () => const VideosState(
      status: VideosStatus.loaded,
      videos: [],
      availableGenres: [VideoGenre.educational, VideoGenre.entertainment],
    ),
    act: (b) => b.add(const VideosCategorySelected(VideoGenre.entertainment)),
    expect: () => [
      isA<VideosState>()
          .having((s) => s.status, 'status', VideosStatus.loading)
          .having((s) => s.selectedGenre, 'selectedGenre',
              VideoGenre.entertainment),
      isA<VideosState>()
          .having((s) => s.status, 'status', VideosStatus.loaded)
          .having((s) => s.videos.single.tag, 'genre',
              VideoGenre.entertainment)
          // the tab strip derived on the All load is preserved.
          .having(
            (s) => s.availableGenres,
            'availableGenres',
            [VideoGenre.educational, VideoGenre.entertainment],
          ),
    ],
    verify: (_) {
      verify(() => repo.fetchFeed(
            gymId: 'g1',
            memberId: 'm1',
            videoType: VideoGenre.entertainment,
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
          )).called(1);
    },
  );

  blocTest<VideosBloc, VideosState>(
    're-tapping the already-selected tab is a no-op (no refetch)',
    setUp: stubFeed,
    build: build,
    seed: () => const VideosState(
      status: VideosStatus.loaded,
      availableGenres: [VideoGenre.educational],
      selectedGenre: VideoGenre.educational,
    ),
    act: (b) => b.add(const VideosCategorySelected(VideoGenre.educational)),
    expect: () => <VideosState>[],
    verify: (_) => verifyNever(() => repo.fetchFeed(
          gymId: any(named: 'gymId'),
          memberId: any(named: 'memberId'),
          videoType: any(named: 'videoType'),
          limit: any(named: 'limit'),
          offset: any(named: 'offset'),
        )),
  );

  blocTest<VideosBloc, VideosState>(
    'a feed failure surfaces a retryable error',
    setUp: () {
      when(() => repo.fetchFeed(
            gymId: any(named: 'gymId'),
            memberId: any(named: 'memberId'),
            videoType: any(named: 'videoType'),
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
          )).thenThrow(const NetworkException('offline'));
    },
    build: build,
    act: (b) => b.add(const VideosLoadRequested()),
    expect: () => [
      isA<VideosState>()
          .having((s) => s.status, 'status', VideosStatus.loading),
      isA<VideosState>()
          .having((s) => s.status, 'status', VideosStatus.error)
          .having((s) => s.errorMessage, 'errorMessage', 'offline'),
    ],
  );

  blocTest<VideosBloc, VideosState>(
    'retrying after an error recovers to a loaded feed',
    setUp: stubFeed,
    build: build,
    seed: () => const VideosState(
      status: VideosStatus.error,
      errorMessage: 'offline',
    ),
    act: (b) => b.add(const VideosLoadRequested()),
    expect: () => [
      isA<VideosState>()
          .having((s) => s.status, 'status', VideosStatus.loading)
          .having((s) => s.errorMessage, 'errorMessage', isNull),
      isA<VideosState>()
          .having((s) => s.status, 'status', VideosStatus.loaded)
          .having((s) => s.videos.length, 'videos', 2),
    ],
  );
}
