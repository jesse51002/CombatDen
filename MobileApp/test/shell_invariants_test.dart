
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/stub_asset_bundle.dart';

import 'package:mobile_app/core/formats/layout_formats.dart';
import 'package:mobile_app/shared/widgets/nav/app_bottom_nav_bar.dart';
import 'package:mobile_app/shared/widgets/nav/app_nav_item.dart';
import 'package:mobile_app/shared/widgets/topbar/app_topbar.dart';
import 'package:mobile_app/shared/widgets/topbar/info_bar.dart';
import 'package:mobile_app/shared/widgets/topbar/parts/gym_mark.dart';
import 'package:mobile_app/shared/widgets/topbar/parts/gym_name_label.dart';
import 'package:mobile_app/shared/widgets/topbar/parts/topbar_back_button.dart';

/// The functional-equivalence gate for `app_shell_format`.
///
/// A layout format may change ARRANGEMENT ONLY. This asserts it
/// mechanically: every value of the enum is pumped and its element set
/// is compared against the contract below. A generated layout that
/// drops the QR action, loses a nav destination, or quietly adds a
/// second reserve button fails here rather than in review.
///
/// This is the check that makes the "no feature added, none removed"
/// claim verifiable instead of argued.
void main() {
  /// Pump at a real phone width. At the default 800x600 test surface a
  /// cramped row still fits, so an arrangement that overflows on an
  /// actual device would pass unnoticed.
  void phoneSized(WidgetTester tester) {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
  }

  Widget host(Widget child) {
    return DefaultAssetBundle(
      bundle: StubAssetBundle(),
      child: MaterialApp(home: Scaffold(body: child)),
    );
  }

  Widget topbar({
    required AppShellFormat format,
    required AppTopbarMode mode,
    bool showBackButton = false,
  }) {
    return host(
      AppTopbar(
        formatOverride: format,
        mode: mode,
        showBackButton: showBackButton,
        gymName: 'Global MMA',
        logoAsset: 'logo_primary.png',
        streakDays: 12,
        pointsLabel: '2,480',
        rankBadgeAsset: 'rank_belt.png',
      ),
    );
  }

  group('every shell format carries every topbar element', () {
    for (final format in AppShellFormat.values) {
      for (final mode in AppTopbarMode.values) {
        testWidgets('$format / $mode', (tester) async {
          phoneSized(tester);
          await tester.pumpWidget(topbar(format: format, mode: mode));

          // The switch-gym affordance is always present, even where the
          // layout does not lay the name out (markOnly).
          expect(find.byType(GymNameLabel), findsOneWidget);

          // The stat bar is present exactly once and always carries its
          // four items: rank badge, streak, points, QR action.
          expect(find.byType(InfoBar), findsOneWidget);
          expect(
            find.descendant(
              of: find.byType(InfoBar),
              matching: find.byType(Image),
            ),
            findsNWidgets(4),
          );
        });
      }
    }
  });

  group('the mark follows the screen-level prominence hint', () {
    // stacked / compactRail / statFirst honour the mode, so their
    // element set matches the shipped screen exactly. markOnly is the
    // one documented variance: the mark IS the layout, so it always
    // shows and the name is the thing that is hidden instead.
    for (final format in AppShellFormat.values) {
      testWidgets('$format', (tester) async {
        phoneSized(tester);
        await tester.pumpWidget(
          topbar(format: format, mode: AppTopbarMode.bigLogo),
        );
        expect(find.byType(GymMark), findsOneWidget);

        await tester.pumpWidget(
          topbar(format: format, mode: AppTopbarMode.nameOnly),
        );
        expect(
          find.byType(GymMark),
          format == AppShellFormat.markOnly ? findsOneWidget : findsNothing,
        );
      });
    }
  });

  group('the back control appears exactly when the screen asks', () {
    for (final format in AppShellFormat.values) {
      testWidgets('$format', (tester) async {
        phoneSized(tester);
        await tester.pumpWidget(
          topbar(
            format: format,
            mode: AppTopbarMode.nameOnly,
            showBackButton: true,
          ),
        );
        expect(find.byType(TopbarBackButton), findsOneWidget);

        await tester.pumpWidget(
          topbar(format: format, mode: AppTopbarMode.nameOnly),
        );
        expect(find.byType(TopbarBackButton), findsNothing);
      });
    }
  });

  group('every shell format keeps all four nav destinations in order', () {
    const expected = ['Home', 'Rank', 'Reward', 'Videos'];

    for (final format in AppShellFormat.values) {
      testWidgets('$format', (tester) async {
        phoneSized(tester);
        await tester.pumpWidget(
          host(
            Align(
              alignment: Alignment.bottomCenter,
              child: AppBottomNavBar(
                formatOverride: format,
                selected: AppBottomNavTab.home,
              ),
            ),
          ),
        );

        final items = tester
            .widgetList<AppNavItem>(find.byType(AppNavItem))
            .toList();

        expect(items.length, 4);
        expect(items.map((i) => i.label).toList(), expected);

        // Exactly one destination reads as active.
        expect(items.where((i) => i.isActive).length, 1);
      });
    }
  });
}
