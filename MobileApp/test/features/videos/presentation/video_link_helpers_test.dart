import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'package:mobile_app/features/videos/data/models/gym_video_card.dart';
import 'package:mobile_app/features/videos/presentation/widgets/gym_video_carousel_card.dart';
import 'package:mobile_app/features/videos/presentation/widgets/video_link_helpers.dart';

import '../../../helpers/fake_url_launcher.dart';

GymVideoCard _card({String url = '', String videoId = ''}) => GymVideoCard(
      videoId: videoId,
      url: url,
      title: 'Guard retention drills',
      thumbnailUrl: 'https://cdn.test/thumb.jpg',
      channelName: 'Combat Culture',
      channelUrl: 'https://youtube.com/@combat',
      channelAvatarUrl: '',
      relevanceIndex: 0,
    );

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('videoUriFor', () {
    test('prefers the card url the feed served', () {
      final uri = videoUriFor(
        _card(url: 'https://youtu.be/abc123XYZ_1', videoId: 'abc123XYZ_1'),
      );

      expect(uri.toString(), 'https://youtu.be/abc123XYZ_1');
    });

    test('falls back to the YouTube watch url built from the video id', () {
      final uri = videoUriFor(_card(videoId: 'abc123XYZ_1'));

      expect(uri.toString(), 'https://www.youtube.com/watch?v=abc123XYZ_1');
    });

    test('treats a blank url as absent', () {
      final uri = videoUriFor(_card(url: '   ', videoId: 'abc123XYZ_1'));

      expect(uri.toString(), 'https://www.youtube.com/watch?v=abc123XYZ_1');
    });

    test('falls back when the url has no scheme to launch', () {
      final uri = videoUriFor(
        _card(url: 'youtu.be/abc123XYZ_1', videoId: 'abc123XYZ_1'),
      );

      expect(uri.toString(), 'https://www.youtube.com/watch?v=abc123XYZ_1');
    });

    test('is null when the card carries neither', () {
      expect(videoUriFor(_card()), isNull);
    });
  });

  group('openVideoFor', () {
    late FakeUrlLauncher launcher;

    setUp(() {
      launcher = FakeUrlLauncher();
      UrlLauncherPlatform.instance = launcher;
    });

    testWidgets('tapping a video card hands the watch url to the OS',
        (tester) async {
      final card = _card(url: 'https://youtu.be/abc123XYZ_1');
      await tester.pumpWidget(
        _host(
          Builder(
            builder: (context) => GymVideoCarouselCard(
              card: card,
              onTap: () => openVideoFor(context, card),
            ),
          ),
        ),
      );

      await tester.tap(find.byType(GymVideoCarouselCard));
      await tester.pump();

      expect(launcher.launched, <String>['https://youtu.be/abc123XYZ_1']);
      // The YouTube app takes it when installed, the browser otherwise —
      // never an in-app web view.
      expect(
        launcher.lastOptions?.mode,
        PreferredLaunchMode.externalApplication,
      );
    });

    testWidgets('builds the fallback url from the video id', (tester) async {
      final card = _card(videoId: 'abc123XYZ_1');
      await tester.pumpWidget(
        _host(
          Builder(
            builder: (context) => GymVideoCarouselCard(
              card: card,
              onTap: () => openVideoFor(context, card),
            ),
          ),
        ),
      );

      await tester.tap(find.byType(GymVideoCarouselCard));
      await tester.pump();

      expect(
        launcher.launched,
        <String>['https://www.youtube.com/watch?v=abc123XYZ_1'],
      );
    });

    testWidgets('tells the member when nothing could open it', (tester) async {
      UrlLauncherPlatform.instance = FakeUrlLauncher(succeeds: false);
      final card = _card(url: 'https://youtu.be/abc123XYZ_1');
      await tester.pumpWidget(
        _host(
          Builder(
            builder: (context) => GymVideoCarouselCard(
              card: card,
              onTap: () => openVideoFor(context, card),
            ),
          ),
        ),
      );

      await tester.tap(find.byType(GymVideoCarouselCard));
      await tester.pump();
      await tester.pump();

      expect(find.text("Couldn't open the video"), findsOneWidget);
    });

    testWidgets('a card with no url and no id never launches', (tester) async {
      final card = _card();
      await tester.pumpWidget(
        _host(
          Builder(
            builder: (context) => GymVideoCarouselCard(
              card: card,
              onTap: () => openVideoFor(context, card),
            ),
          ),
        ),
      );

      await tester.tap(find.byType(GymVideoCarouselCard));
      await tester.pump();
      await tester.pump();

      expect(launcher.launched, isEmpty);
      expect(find.text("Couldn't open the video"), findsOneWidget);
    });
  });
}
