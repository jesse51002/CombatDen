import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_app/shared/widgets/nav/app_bottom_nav_bar.dart';
import 'package:mobile_app/shared/widgets/nav/app_nav_item.dart';
import 'package:mobile_app/shared/widgets/nav/nav_tabs.dart';

Widget _host(List<AppBottomNavTab> tabs) => MaterialApp(
      home: Scaffold(
        bottomNavigationBar: AppBottomNavBar(
          selected: AppBottomNavTab.home,
          tabs: tabs,
        ),
      ),
    );

/// The bar's full width — the cell rule is a quarter of THIS, always.
double _barWidth(WidgetTester tester) =>
    tester.getSize(find.byType(AppBottomNavBar)).width;

/// Every rendered cell's width, left to right.
List<double> _cellWidths(WidgetTester tester) => tester
    .widgetList<AppNavItem>(find.byType(AppNavItem))
    .map((item) => tester.getSize(find.byWidget(item)).width)
    .toList(growable: false);

/// Every rendered cell's left edge, left to right.
List<double> _cellLefts(WidgetTester tester) => tester
    .widgetList<AppNavItem>(find.byType(AppNavItem))
    .map((item) => tester.getTopLeft(find.byWidget(item)).dx)
    .toList(growable: false);

void main() {
  group('AppBottomNavBar tab set', () {
    testWidgets('the rank tab is LABELLED "Profile"', (tester) async {
      await tester.pumpWidget(_host(AppBottomNavTab.values));

      expect(find.text('Profile'), findsOneWidget);
      expect(find.text('Rank'), findsNothing);
    });

    testWidgets('four tabs render at a quarter each, edge to edge',
        (tester) async {
      await tester.pumpWidget(_host(AppBottomNavTab.values));
      final cell = _barWidth(tester) / 4;

      expect(find.byType(AppNavItem), findsNWidgets(4));
      expect(_cellWidths(tester), everyElement(closeTo(cell, 0.01)));
      // No gutter at four — identical to the old Expanded split.
      expect(_cellLefts(tester).first, closeTo(0, 0.01));
      expect(
        _cellLefts(tester).last + cell,
        closeTo(_barWidth(tester), 0.01),
      );
    });

    testWidgets('three tabs keep the quarter cell and gain a symmetric gutter',
        (tester) async {
      await tester.pumpWidget(
        _host(const [
          AppBottomNavTab.home,
          AppBottomNavTab.rank,
          AppBottomNavTab.videos,
        ]),
      );
      final cell = _barWidth(tester) / 4;

      expect(find.byType(AppNavItem), findsNWidgets(3));
      expect(_cellWidths(tester), everyElement(closeTo(cell, 0.01)));

      final lefts = _cellLefts(tester);
      final leftGutter = lefts.first;
      final rightGutter = _barWidth(tester) - (lefts.last + cell);
      expect(leftGutter, closeTo(rightGutter, 0.01));
      expect(leftGutter, closeTo(cell / 2, 0.01));
    });

    testWidgets('two tabs are a CENTRED pair, not stretched halves',
        (tester) async {
      await tester.pumpWidget(
        _host(const [AppBottomNavTab.home, AppBottomNavTab.rank]),
      );
      final cell = _barWidth(tester) / 4;

      expect(find.byType(AppNavItem), findsNWidgets(2));
      // The killer case: an Expanded split would make each cell HALF the bar
      // and maroon a 24pt icon in half a phone.
      expect(_cellWidths(tester), everyElement(closeTo(cell, 0.01)));

      final lefts = _cellLefts(tester);
      expect(lefts.first, closeTo(cell, 0.01));
      expect(
        _barWidth(tester) - (lefts.last + cell),
        closeTo(cell, 0.01),
      );
    });
  });

  group('navTabsFor', () {
    test('a gym with everything gets the full set in enum order', () {
      expect(
        navTabsFor(hasRewards: true, hasVideos: true),
        AppBottomNavTab.values,
      );
    });

    test('no rewards drops ONLY the reward tab', () {
      expect(navTabsFor(hasRewards: false, hasVideos: true), const [
        AppBottomNavTab.home,
        AppBottomNavTab.rank,
        AppBottomNavTab.videos,
      ]);
    });

    test('no videos drops ONLY the videos tab', () {
      expect(navTabsFor(hasRewards: true, hasVideos: false), const [
        AppBottomNavTab.home,
        AppBottomNavTab.rank,
        AppBottomNavTab.reward,
      ]);
    });

    test('Home and Profile are structural — they survive everything', () {
      expect(navTabsFor(hasRewards: false, hasVideos: false), const [
        AppBottomNavTab.home,
        AppBottomNavTab.rank,
      ]);
    });
  });
}
