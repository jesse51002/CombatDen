import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/stub_asset_bundle.dart';

import 'package:mobile_app/core/app_slots.dart';
import 'package:mobile_app/core/formats/dev/format_panel.dart';
import 'package:mobile_app/core/formats/format_store.dart';
import 'package:mobile_app/core/formats/layout_formats.dart';
import 'package:mobile_app/core/formats/theme_layout.dart';
import 'package:mobile_app/shared/widgets/scaffold/app_screen_scaffold.dart';
import 'package:mobile_app/shared/widgets/topbar/app_topbar.dart';
import 'package:mobile_app/shared/widgets/topbar/layouts/topbar_mark_only.dart';
import 'package:mobile_app/shared/widgets/topbar/layouts/topbar_stacked.dart';

/// The dev picker's contract: pinning a format takes effect immediately,
/// in place, without a rebuild of the app or a reset of navigation.
void main() {
  tearDown(FormatStore.instance.reset);

  test('an unpinned slot resolves to the shipped arrangement', () {
    expect(FormatStore.instance.isEmpty, isTrue);
    expect(ThemeLayout.shell(), AppShellFormat.stacked);
  });

  test('pinning a slot wins over the shipped fallback', () {
    FormatStore.instance.set(CombatDenSlots.appShellFormat, 'markOnly');
    expect(ThemeLayout.shell(), AppShellFormat.markOnly);

    FormatStore.instance.set(CombatDenSlots.appShellFormat, null);
    expect(ThemeLayout.shell(), AppShellFormat.stacked);
  });

  test('an unrecognised pin degrades to the shipped arrangement', () {
    FormatStore.instance.set(CombatDenSlots.appShellFormat, 'nonsense');
    expect(ThemeLayout.shell(), AppShellFormat.stacked);
  });

  testWidgets('switching swaps the live topbar without a remount', (
    tester,
  ) async {
    await tester.pumpWidget(
      withStubAssets(MaterialApp(
        home: Scaffold(
          body: AppTopbar(
            mode: AppTopbarMode.bigLogo,
            showBackButton: false,
            gymName: 'Global MMA',
            logoAsset: 'logo_primary.png',
            streakDays: 12,
            pointsLabel: '2,480',
            rankBadgeAsset: 'rank_belt.png',
          ),
        ),
      )),
    );
    expect(find.byType(TopbarStacked), findsOneWidget);

    // No pumpWidget: exactly what the panel does at runtime.
    FormatStore.instance.set(CombatDenSlots.appShellFormat, 'markOnly');
    await tester.pump();

    expect(find.byType(TopbarMarkOnly), findsOneWidget);
    expect(find.byType(TopbarStacked), findsNothing);
  });

  testWidgets('the picker is reachable as a drawer on a screen', (
    tester,
  ) async {
    await tester.pumpWidget(
      withStubAssets(
        const MaterialApp(
          home: AppScreenScaffold(child: SizedBox.shrink()),
        ),
      ),
    );

    // Debug builds attach it; this also compiles the whole panel graph.
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
    expect(scaffold.drawer, isA<FormatPanel>());

    tester.state<ScaffoldState>(find.byType(Scaffold).first).openDrawer();
    await tester.pumpAndSettle();
    expect(find.text('Formats'), findsOneWidget);
    expect(find.text('markOnly'), findsOneWidget);
  });
}
