import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_app/core/app_routes.dart';
import 'package:mobile_app/shared/widgets/topbar/info_bar.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

Widget _infoBar({
  String? rankImageUrl,
  bool showRank = true,
  bool pointsSpendable = true,
}) =>
    InfoBar(
      rankBadgeAsset: 'icon_rank_belt.png',
      rankImageUrl: rankImageUrl,
      showRank: showRank,
      pointsSpendable: pointsSpendable,
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

/// Every belt-sized image in the bar — empty when the rank tile is collapsed.
List<Image> _beltImages(WidgetTester tester) => tester
    .widgetList<Image>(
      find.descendant(of: find.byType(InfoBar), matching: find.byType(Image)),
    )
    .where((i) => i.width == 39 && i.height == 24)
    .toList(growable: false);

double _barWidth(WidgetTester tester) =>
    tester.getSize(find.byType(InfoBar)).width;

/// The bar's tile CELLS — the direct children of its outer row.
List<Widget> _cells(WidgetTester tester) => tester
    .widget<Row>(
      find.descendant(of: find.byType(InfoBar), matching: find.byType(Row)).first,
    )
    .children;

/// A host that records the route names the bar pushes.
Widget _routedHost(Widget child, List<String?> pushed) => MaterialApp(
      home: Scaffold(body: child),
      onGenerateRoute: (settings) {
        pushed.add(settings.name);
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => const SizedBox.shrink(),
        );
      },
    );

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

  group('InfoBar tile set', () {
    testWidgets('a rank-off gym COLLAPSES the belt tile entirely',
        (tester) async {
      await tester.pumpWidget(_host(_infoBar(showRank: false)));

      // No belt at all — not the themed fallback either. A fallback belt on
      // every screen would advertise a ladder the gym doesn't run.
      expect(_beltImages(tester), isEmpty);
      expect(_cells(tester), hasLength(3));
      // The other three tiles survive.
      expect(find.text('3'), findsOneWidget);
      expect(find.text('120'), findsOneWidget);
    });

    testWidgets('four tiles span the bar at a quarter each', (tester) async {
      await tester.pumpWidget(_host(_infoBar()));
      final cell = _barWidth(tester) / 4;
      final cells = _cells(tester);

      expect(cells, hasLength(4));
      expect(
        cells.map((c) => tester.getSize(find.byWidget(c)).width),
        everyElement(closeTo(cell, 0.01)),
      );
      expect(tester.getTopLeft(find.byWidget(cells.first)).dx, closeTo(0, 0.01));
    });

    testWidgets('three tiles keep the quarter cell and centre the row',
        (tester) async {
      await tester.pumpWidget(_host(_infoBar(showRank: false)));
      final cell = _barWidth(tester) / 4;
      final cells = _cells(tester);

      expect(
        cells.map((c) => tester.getSize(find.byWidget(c)).width),
        everyElement(closeTo(cell, 0.01)),
      );
      final left = tester.getTopLeft(find.byWidget(cells.first)).dx;
      final right =
          _barWidth(tester) - tester.getTopRight(find.byWidget(cells.last)).dx;
      expect(left, closeTo(right, 0.01));
      expect(left, closeTo(cell / 2, 0.01));
    });
  });

  group('InfoBar points tile', () {
    testWidgets('links into the store when the gym HAS rewards',
        (tester) async {
      final pushed = <String?>[];
      await tester.pumpWidget(_routedHost(_infoBar(), pushed));

      await tester.tap(find.text('120'));
      await tester.pumpAndSettle();

      expect(pushed, [AppRoutes.pointsStore]);
    });

    testWidgets('is a plain READ-OUT when the gym has no rewards',
        (tester) async {
      final pushed = <String?>[];
      await tester.pumpWidget(
        _routedHost(_infoBar(pointsSpendable: false), pushed),
      );

      // The number still shows — it is real earned attendance — but it is no
      // longer a doorway into a store with nothing in it.
      expect(find.text('120'), findsOneWidget);
      await tester.tap(find.text('120'));
      await tester.pumpAndSettle();
      expect(pushed, isEmpty);
    });

    testWidgets('the streak tile still reaches the profile either way',
        (tester) async {
      final pushed = <String?>[];
      await tester.pumpWidget(
        _routedHost(_infoBar(pointsSpendable: false, showRank: false), pushed),
      );

      await tester.tap(find.text('3'));
      await tester.pumpAndSettle();

      expect(pushed, [AppRoutes.profile]);
    });
  });
}
