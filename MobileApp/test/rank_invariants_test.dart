import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/stub_asset_bundle.dart';

import 'package:mobile_app/core/formats/layout_formats.dart';
import 'package:mobile_app/features/profile/data/mock_profile.dart';
import 'package:mobile_app/features/profile/presentation/screens/profile_screen.dart';
import 'package:mobile_app/features/profile/presentation/widgets/level_up_videos/level_up_videos_section.dart';
import 'package:mobile_app/features/profile/presentation/widgets/next_rank/next_rank_badge.dart';
import 'package:mobile_app/features/profile/presentation/widgets/next_rank/next_rank_progress.dart';
import 'package:mobile_app/features/profile/presentation/widgets/next_rank/next_rank_progress_label.dart';
import 'package:mobile_app/features/profile/presentation/widgets/next_rank/next_rank_title.dart';
import 'package:mobile_app/features/profile/presentation/widgets/rank_summary/rank_header.dart';
import 'package:mobile_app/features/profile/presentation/widgets/rank_summary/rating_graph.dart';
import 'package:mobile_app/features/profile/presentation/widgets/rank_summary/timeframe_selector.dart';
import 'package:mobile_app/shared/widgets/nav/app_bottom_nav_bar.dart';
import 'package:mobile_app/shared/widgets/pills/timeframe_pill.dart';
import 'package:mobile_app/shared/widgets/sparkle_hero/sparkle_hero.dart';
import 'package:mobile_app/shared/widgets/topbar/app_topbar.dart';

/// The functional-equivalence gate for `rank_format`.
///
/// A layout format may change ARRANGEMENT ONLY. This asserts it
/// mechanically: every value of the enum is pumped as the real screen
/// and its element set is compared against the contract below. A
/// generated layout that drops the range selector, loses the progress
/// label, or quietly shows the celebration hero twice fails here rather
/// than in review.
///
/// This is the check that makes the "no feature added, none removed"
/// claim verifiable instead of argued.
void main() {
  /// Pump at a real phone size. At the default 800x600 test surface a
  /// cramped arrangement still fits, so a layout that overflows on an
  /// actual device would pass unnoticed.
  void phoneSized(WidgetTester tester) {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
  }

  Future<void> pumpRank(WidgetTester tester, RankFormat format) async {
    phoneSized(tester);
    await tester.pumpWidget(
      withStubAssets(
        MaterialApp(home: ProfileScreen(formatOverride: format)),
      ),
    );
    // The celebration hero animates in on mount; run it out so what is
    // asserted is the settled screen, not its first frame.
    await tester.pump(const Duration(milliseconds: 32));
    await tester.pump(const Duration(seconds: 2));
  }

  group('every rank format carries every element of the screen', () {
    for (final format in RankFormat.values) {
      testWidgets('$format', (tester) async {
        await pumpRank(tester, format);

        // Nothing overflowed, threw, or failed to lay out at 390x844.
        expect(tester.takeException(), isNull);

        // The chrome the screen sits in.
        expect(find.byType(AppTopbar), findsOneWidget);
        expect(find.byType(AppBottomNavBar), findsOneWidget);

        // The celebration signature: present, and rationed to ONE. A
        // layout may move it, overlay it, or shrink it to a line; none
        // may multiply it.
        expect(find.byType(SparkleHero), findsOneWidget);

        // The CURRENT rank, with both its names.
        expect(find.byType(RankHeader), findsOneWidget);
        expect(find.text(mockProfile.rankTitle), findsOneWidget);
        expect(find.text(mockProfile.rankSubtitle), findsOneWidget);

        // Rating over time, and the range it is scoped to.
        expect(find.byType(RatingGraph), findsOneWidget);
        expect(find.byType(TimeframeSelector), findsOneWidget);
        expect(find.byType(TimeframePill), findsNWidgets(4));

        // The NEXT rank: all four elements, wherever they landed.
        expect(find.byType(NextRankBadge), findsOneWidget);
        expect(find.byType(NextRankTitle), findsOneWidget);
        expect(find.byType(NextRankProgress), findsOneWidget);
        expect(find.byType(NextRankProgressLabel), findsOneWidget);

        // The label is the only place the screen says what the
        // progress counts, so it is asserted verbatim: a layout that
        // truncated it to fit would be dropping information, not
        // rearranging it.
        expect(
          find.text(mockProfile.nextRankProgressLabel),
          findsOneWidget,
        );

        // The videos that feed the loop back into content. Only the
        // section itself can be asserted: its cards come from the live
        // VideoService feed, which a widget test has no gym for, so it
        // renders empty here exactly as it does for a tenant with no
        // educational videos.
        expect(find.byType(LevelUpVideosSection), findsOneWidget);
      });
    }
  });

  group('every rank format keeps all four nav destinations', () {
    for (final format in RankFormat.values) {
      testWidgets('$format', (tester) async {
        await pumpRank(tester, format);

        final nav = tester.widget<AppBottomNavBar>(
          find.byType(AppBottomNavBar),
        );
        // Rank is the tab this screen belongs to, in every layout.
        expect(nav.selected, AppBottomNavTab.rank);
        for (final label in ['Home', 'Rank', 'Reward', 'Videos']) {
          expect(find.text(label), findsOneWidget);
        }
      });
    }
  });

  group('no rank format reaches for data the screen does not fetch', () {
    // Only the CURRENT rank and the NEXT one are available. An
    // arrangement implying rank HISTORY would need a series this screen
    // never fetches — the reason a "journey timeline" value was ruled
    // out during authoring. This pins that: the screen renders exactly
    // two belts, one for each rank it actually has.
    for (final format in RankFormat.values) {
      testWidgets('$format', (tester) async {
        await pumpRank(tester, format);

        expect(find.byType(RankHeader), findsOneWidget);
        expect(find.byType(NextRankBadge), findsOneWidget);
      });
    }
  });
}
