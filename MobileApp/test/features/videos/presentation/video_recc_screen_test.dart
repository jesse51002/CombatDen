import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'package:mobile_app/core/state/selected_member.dart';
import 'package:mobile_app/features/videos/data/models/gym_video_card.dart';
import 'package:mobile_app/features/videos/data/models/member_video_rec.dart';
import 'package:mobile_app/features/videos/data/models/video_genre.dart';
import 'package:mobile_app/features/videos/data/repositories/member_videos_repository.dart';
import 'package:mobile_app/features/videos/presentation/screens/video_recc_screen.dart';

import '../../../helpers/fake_url_launcher.dart';

class _MockVideosRepository extends Mock implements MemberVideosRepository {}

const String _kWatchUrl = 'https://youtu.be/abc123XYZ_1';

final MemberVideoRec _rec = const MemberVideoRec(
  recId: 'rec-1',
  category: VideoGenre.educational,
  video: GymVideoCard(
    videoId: 'abc123XYZ_1',
    url: _kWatchUrl,
    title: 'Guard retention drills',
    thumbnailUrl: 'https://cdn.test/thumb.jpg',
    channelName: 'Combat Culture',
    channelUrl: 'https://youtube.com/@combat',
    channelAvatarUrl: '',
    relevanceIndex: 0,
  ),
);

void main() {
  late _MockVideosRepository repository;
  late FakeUrlLauncher launcher;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await selectedMember.select(
      memberId: 'member-1',
      gymId: 'gym-1',
      gymName: 'Iron Fist MMA',
      firstName: 'Ada',
      lastName: 'Lovelace',
    );

    launcher = FakeUrlLauncher();
    UrlLauncherPlatform.instance = launcher;

    repository = _MockVideosRepository();
    when(
      () => repository.fetchRec(
        gymId: any(named: 'gymId'),
        memberId: any(named: 'memberId'),
      ),
    ).thenAnswer((_) async => _rec);
    when(
      () => repository.recordRecClick(
        gymId: any(named: 'gymId'),
        memberId: any(named: 'memberId'),
        recId: any(named: 'recId'),
      ),
    ).thenAnswer((_) async {});
  });

  tearDown(() async {
    await selectedMember.reset();
  });

  /// Pushes the rec screen over a plain host route, so a pop is observable.
  /// Sized to a phone: the full-bleed 16:9 card doesn't fit the 800x600 test
  /// surface.
  Future<void> pumpRec(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: const Scaffold(body: Center(child: Text('behind'))),
      ),
    );
    unawaited(
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => VideoReccScreen(repository: repository),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('VideoReccScreen "Watch"', () {
    testWidgets('records the click AND opens the video, then closes',
        (tester) async {
      await pumpRec(tester);
      expect(find.text('Watch'), findsOneWidget);

      await tester.tap(find.text('Watch'));
      await tester.pumpAndSettle();

      // The click feeds the member's video profile — it must still fire.
      verify(
        () => repository.recordRecClick(
          gymId: 'gym-1',
          memberId: 'member-1',
          recId: 'rec-1',
        ),
      ).called(1);
      expect(launcher.launched, <String>[_kWatchUrl]);
      expect(
        launcher.lastOptions?.mode,
        PreferredLaunchMode.externalApplication,
      );
      // The video is on its way out, so the rec surface steps aside.
      expect(find.text('behind'), findsOneWidget);
      expect(find.text('Watch'), findsNothing);
    });

    testWidgets('keeps the rec on screen when nothing can open it',
        (tester) async {
      UrlLauncherPlatform.instance = FakeUrlLauncher(succeeds: false);

      await pumpRec(tester);
      await tester.tap(find.text('Watch'));
      await tester.pumpAndSettle();

      verify(
        () => repository.recordRecClick(
          gymId: 'gym-1',
          memberId: 'member-1',
          recId: 'rec-1',
        ),
      ).called(1);
      expect(find.text("Couldn't open the video"), findsOneWidget);
      // Still there to retry — a failed launch never eats the recommendation.
      expect(find.text('Watch'), findsOneWidget);
    });
  });
}
