import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_app/features/stats/data/mock_stats.dart';
import 'package:mobile_app/features/stats/presentation/widgets/rank/rank_body.dart';

Widget _host({String? rankImageUrl}) => MaterialApp(
      home: Scaffold(
        body: RankBody(
          stats: MockRankStats(
            rankTitle: 'Blue Belt',
            rankSubtitle: 'Stripe II',
            beltAsset: 'stat_rank_belt.png',
            rankImageUrl: rankImageUrl,
            nextTierLabel: '',
            classesAttended: 28,
            classesRequired: 50,
          ),
        ),
      ),
    );

/// Every belt on screen — the card's only image, in whichever phase the
/// animation is in. It must always be exactly one.
final Finder _belts =
    find.descendant(of: find.byType(RankBody), matching: find.byType(Image));

final Finder _beltFinder = _belts.first;

ImageProvider _beltProvider(WidgetTester tester) =>
    tester.widget<Image>(_beltFinder).image;

void main() {
  group("the celebration belt is the MEMBER's, not the theme's", () {
    testWidgets("renders the member's own rank art when it has one",
        (tester) async {
      await tester.pumpWidget(_host(rankImageUrl: 'https://cdn.test/blue.png'));

      final provider = _beltProvider(tester);
      expect(provider, isA<CachedNetworkImageProvider>());
      expect(
        (provider as CachedNetworkImageProvider).url,
        'https://cdn.test/blue.png',
      );

      await tester.pumpAndSettle();
    });

    testWidgets('falls back to the themed belt when the rank has no art',
        (tester) async {
      await tester.pumpWidget(_host());

      expect(_beltProvider(tester), isNot(isA<CachedNetworkImageProvider>()));

      await tester.pumpAndSettle();
    });

    testWidgets('treats a blank URL as absent, not as a broken image',
        (tester) async {
      await tester.pumpWidget(_host(rankImageUrl: '   '));

      expect(_beltProvider(tester), isNot(isA<CachedNetworkImageProvider>()));

      await tester.pumpAndSettle();
    });

    testWidgets('a failed load falls back to the themed belt, not a hole',
        (tester) async {
      await tester.pumpWidget(_host(rankImageUrl: 'https://cdn.test/404.png'));

      final image = tester.widget<Image>(_beltFinder);
      expect(image.errorBuilder, isNotNull);
      final onError = image.errorBuilder!(
        tester.element(_beltFinder),
        Exception('404'),
        StackTrace.empty,
      );
      await tester.pumpAndSettle();

      // Build what a 404 actually paints: still a belt, on the themed/bundled
      // provider — the card never lands an empty slot.
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: onError)));
      final fallback = tester.widget<Image>(find.byType(Image));
      expect(fallback.image, isNot(isA<CachedNetworkImageProvider>()));
      expect(fallback.fit, BoxFit.contain);
    });
  });

  group('the belt animation still runs', () {
    testWidgets('ONE belt flies from centre stage into the measured slot',
        (tester) async {
      await tester.pumpWidget(_host(rankImageUrl: 'https://cdn.test/blue.png'));
      await tester.pump(const Duration(milliseconds: 16));

      expect(_belts, findsOneWidget);
      final bodyCentre = tester.getCenter(find.byType(RankBody));
      final entranceCentre = tester.getCenter(_beltFinder);
      final entranceSize = tester.getSize(_beltFinder);
      expect(entranceCentre.dx, closeTo(bodyCentre.dx, 0.01));
      expect(entranceCentre.dy, closeTo(bodyCentre.dy, 0.01));
      expect(entranceSize.width, greaterThan(77));

      await tester.pumpAndSettle();

      // Landed: still ONE belt, now filling the rank row's 77x50 slot.
      expect(_belts, findsOneWidget);
      final landedSize = tester.getSize(_beltFinder);
      expect(landedSize.width, closeTo(77, 0.01));
      expect(landedSize.height, closeTo(50, 0.01));
      expect(tester.getCenter(_beltFinder), isNot(entranceCentre));
    });
  });
}
