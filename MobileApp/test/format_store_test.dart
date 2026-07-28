import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/stub_asset_bundle.dart';
import 'helpers/stub_theme_service.dart';

import 'package:mobile_app/core/app_slots.dart';
import 'package:mobile_app/core/formats/dev/format_panel.dart';
import 'package:mobile_app/core/formats/format_catalog.dart';
import 'package:mobile_app/core/formats/format_resolver.dart';
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

  testWidgets('the picker is reachable from its handle on a screen', (
    tester,
  ) async {
    await tester.pumpWidget(
      withStubAssets(
        const MaterialApp(
          home: AppScreenScaffold(child: SizedBox.shrink()),
        ),
      ),
    );

    // An END drawer, opened only by its own handle: both screen edges
    // belong to Android's system back gesture.
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
    expect(scaffold.endDrawer, isA<FormatPanel>());
    expect(scaffold.endDrawerEnableOpenDragGesture, isFalse);

    // Tapping the visible handle is the only way in.
    await tester.tap(find.text('FMT'));
    await tester.pumpAndSettle();
    expect(find.text('Formats'), findsOneWidget);
    expect(find.text('markOnly'), findsOneWidget);
  });

  /// The theme carries its own format slots, so it must be able to move
  /// them. Before this group existed, a single tap in the picker froze a
  /// slot for the rest of the session and every theme loaded afterwards
  /// silently failed to change it.
  group('a theme load sets the formats and releases every pin', () {
    const slot = CombatDenSlots.appShellFormat;

    test('a theme slot beats the shipped fallback', () {
      final theme = StubThemeService({slot: 'markOnly'});
      addTearDown(installStubTheme(theme));

      expect(ThemeLayout.shell(), AppShellFormat.markOnly);
      expect(FormatResolver.sourceOf(slot), FormatSource.tenant);
    });

    test('a pin beats the theme', () {
      final theme = StubThemeService({slot: 'markOnly'});
      addTearDown(installStubTheme(theme));

      FormatStore.instance.set(slot, 'compactRail');
      expect(ThemeLayout.shell(), AppShellFormat.compactRail);
      expect(FormatResolver.sourceOf(slot), FormatSource.pinned);
    });

    test('loading a theme releases the pin, and the theme wins', () {
      final theme = StubThemeService({slot: 'markOnly'});
      addTearDown(installStubTheme(theme));
      FormatStore.instance.bindTo(theme);

      FormatStore.instance.set(slot, 'compactRail');
      expect(ThemeLayout.shell(), AppShellFormat.compactRail);

      // The gym switch: ThemeRuntime.selectDesign -> notifyListeners.
      theme.load({slot: 'stacked'});

      expect(FormatStore.instance.isEmpty, isTrue);
      expect(ThemeLayout.shell(), AppShellFormat.stacked);
      expect(FormatResolver.sourceOf(slot), FormatSource.tenant);
    });

    test('a theme load releases pins it says nothing about', () {
      final theme = StubThemeService({slot: 'markOnly'});
      addTearDown(installStubTheme(theme));
      FormatStore.instance.bindTo(theme);

      FormatStore.instance.set(CombatDenSlots.homeFormat, 'agendaFirst');
      theme.load({slot: 'markOnly'});

      expect(
        FormatStore.instance.isEmpty,
        isTrue,
        reason: 'a half-cleared picker is not reasonable to review against',
      );
    });

    test('Reset returns to the theme, not to the shipped value', () {
      final theme = StubThemeService({slot: 'markOnly'});
      addTearDown(installStubTheme(theme));

      FormatStore.instance.set(slot, 'compactRail');
      FormatStore.instance.reset();

      expect(ThemeLayout.shell(), AppShellFormat.markOnly);
      expect(FormatResolver.sourceOf(slot), FormatSource.tenant);
    });

    test('an unrecognised theme value degrades to the shipped value', () {
      final theme = StubThemeService({slot: 'nonsense'});
      addTearDown(installStubTheme(theme));

      expect(ThemeLayout.shell(), AppShellFormat.stacked);
    });
  });

  testWidgets('the panel shows exactly what the resolver resolves', (
    tester,
  ) async {
    const slot = CombatDenSlots.appShellFormat;
    final theme = StubThemeService({slot: 'markOnly'});
    addTearDown(installStubTheme(theme));

    Future<void> openPanel() async {
      await tester.pumpWidget(
        withStubAssets(
          const MaterialApp(home: AppScreenScaffold(child: SizedBox.shrink())),
        ),
      );
      await tester.tap(find.text('FMT'));
      await tester.pumpAndSettle();
    }

    /// The value the panel is drawing as live for [slot], read off the
    /// chip it marked rather than inferred from a decoration.
    String shown() {
      final label = tester
          .widget<Text>(
            find.descendant(
              of: find.byKey(selectedChipKey(slot)),
              matching: find.byType(Text),
            ),
          )
          .data!;
      // A pinned chip carries a trailing marker.
      return label.split('  ').first;
    }

    // Theme-sourced: the case the panel used to get wrong, because its
    // own copy of the chain had no tenant step and it drew `stacked`.
    await openPanel();
    expect(shown(), FormatResolver.resolve(slot, AppShellFormat.stacked.name));
    expect(shown(), 'markOnly');
    expect(find.text(FormatSource.tenant.label), findsWidgets);

    // Pinned: the pin wins, and the row says so.
    FormatStore.instance.set(slot, 'compactRail');
    await tester.pumpAndSettle();
    expect(shown(), FormatResolver.resolve(slot, AppShellFormat.stacked.name));
    expect(shown(), 'compactRail');
    expect(find.text(FormatSource.pinned.label), findsWidgets);

    // Released: back to the theme, not to the shipped value.
    FormatStore.instance.reset();
    await tester.pumpAndSettle();
    expect(shown(), 'markOnly');
  });

  test('every catalog entry resolves through the one shared chain', () {
    final theme = StubThemeService({
      for (final entry in [...kLayoutFormats, ...kMotionFormats])
        entry.slot: entry.values.last,
    });
    addTearDown(installStubTheme(theme));

    for (final entry in [...kLayoutFormats, ...kMotionFormats]) {
      expect(
        FormatResolver.resolve(entry.slot, entry.shipped),
        entry.values.last,
        reason: '${entry.slot} did not read its theme value',
      );
      expect(FormatResolver.sourceOf(entry.slot), FormatSource.tenant);
    }
  });
}
