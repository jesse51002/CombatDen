import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_app/shared/widgets/topbar/info_bar.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

Widget _infoBar({String? rankImageUrl}) => InfoBar(
      rankBadgeAsset: 'icon_rank_belt.png',
      rankImageUrl: rankImageUrl,
      streakDays: 3,
      pointsLabel: '120',
    );

/// The provider backing the belt [Image] — the info bar's FIRST image (the
/// rank tile leads the row, ahead of the streak / points / QR tiles).
ImageProvider _beltProvider(WidgetTester tester) {
  final image = tester.widget<Image>(_beltFinder);
  return image.image;
}

final Finder _beltFinder = find
    .descendant(of: find.byType(InfoBar), matching: find.byType(Image))
    .first;

void main() {
  group('InfoBar rank belt', () {
    testWidgets("renders the member's own rank art when a URL is present",
        (tester) async {
      await tester.pumpWidget(
        _host(_infoBar(rankImageUrl: 'https://cdn.test/purple.png')),
      );

      final provider = _beltProvider(tester);
      expect(provider, isA<CachedNetworkImageProvider>());
      expect((provider as CachedNetworkImageProvider).url,
          'https://cdn.test/purple.png');
    });

    testWidgets('falls back to the themed/bundled belt when the URL is null',
        (tester) async {
      await tester.pumpWidget(_host(_infoBar()));

      expect(_beltProvider(tester), isNot(isA<CachedNetworkImageProvider>()));
    });

    testWidgets('falls back when the URL is an empty string', (tester) async {
      await tester.pumpWidget(_host(_infoBar(rankImageUrl: '')));

      expect(_beltProvider(tester), isNot(isA<CachedNetworkImageProvider>()));
    });

    testWidgets('a failed load falls back to the themed belt, not a hole',
        (tester) async {
      await tester.pumpWidget(
        _host(_infoBar(rankImageUrl: 'https://cdn.test/purple.png')),
      );

      final image = tester.widget<Image>(_beltFinder);
      expect(image.errorBuilder, isNotNull);

      // Build what the error path actually renders: still a belt image, on the
      // themed/bundled provider — the topbar chrome never collapses.
      final onError = image.errorBuilder!(
        tester.element(_beltFinder),
        Exception('404'),
        StackTrace.empty,
      );
      await tester.pumpWidget(_host(onError));

      final fallback = tester.widget<Image>(find.byType(Image));
      expect(fallback.image, isNot(isA<CachedNetworkImageProvider>()));
      expect(fallback.width, 39);
      expect(fallback.height, 24);
    });

    testWidgets('keeps the belt at its 39x24 box either way', (tester) async {
      await tester.pumpWidget(
        _host(_infoBar(rankImageUrl: 'https://cdn.test/purple.png')),
      );
      var belt = tester.widget<Image>(_beltFinder);
      expect(belt.width, 39);
      expect(belt.height, 24);
      expect(belt.fit, BoxFit.contain);

      await tester.pumpWidget(_host(_infoBar()));
      belt = tester.widget<Image>(_beltFinder);
      expect(belt.width, 39);
      expect(belt.height, 24);
      expect(belt.fit, BoxFit.contain);
    });
  });
}
