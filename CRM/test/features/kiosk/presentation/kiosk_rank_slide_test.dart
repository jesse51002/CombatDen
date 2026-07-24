import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/kiosk/presentation/widgets/get_app/slides/kiosk_rank_progress.dart';
import 'package:crm/features/kiosk/presentation/widgets/get_app/slides/kiosk_rank_slide.dart';
import 'package:crm/features/memberships/data/models/main_rank.dart';
import 'package:crm/shared/widgets/rank_belt_image.dart';

MainRank _rank(String name, int order, {int classesToNextMajor = 25}) =>
    MainRank(
      rankId: 'rank-$name',
      gymId: 'gym-1',
      mainRankNumOrder: order,
      name: name,
      classesToNextMajor: classesToNextMajor,
      createdAt: DateTime.utc(2026),
    );

/// The "Track rank" showcase slide.
///
/// Its featured rung and its progress numbers are ILLUSTRATIVE ON PURPOSE
/// (founder ruling): kiosk users skew new, so wiring it to the real member
/// pinned the highlight to the first rung with an empty bar — the least
/// compelling thing the feature can look like. These tests pin that decision
/// down so nobody "fixes" it back: always a MIDDLE rung, always a partly
/// filled bar, never a claim that either belongs to the person standing there.
void main() {
  Future<void> pumpSlide(
    WidgetTester tester,
    List<MainRank> ladder, {
    Size surface = const Size(600, 500),
  }) async {
    await tester.binding.setSurfaceSize(surface);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(child: KioskRankSlide(ladder: kioskRankSteps(ladder))),
        ),
      ),
    );
    await tester.pump();
  }

  /// The featured belt is the only one drawn at [rankBeltLarge].
  RankBeltImage featuredBelt(WidgetTester tester) =>
      tester.widgetList<RankBeltImage>(find.byType(RankBeltImage)).firstWhere(
            (b) => b.size == DesignConstants.rankBeltLarge,
          );

  group('the featured rung is a MIDDLE one, never a member\'s', () {
    testWidgets('a five-belt ladder features the third belt', (tester) async {
      await pumpSlide(tester, [
        _rank('White', 1),
        _rank('Blue', 2),
        _rank('Purple', 3),
        _rank('Brown', 4),
        _rank('Black', 5),
      ]);

      expect(featuredBelt(tester).imageUrl, isNull);
      // Exactly one rung is large + un-dimmed; the rest rest at belt-XSmall.
      final belts = tester.widgetList<RankBeltImage>(
        find.byType(RankBeltImage),
      );
      expect(
        belts.where((b) => b.size == DesignConstants.rankBeltLarge).length,
        1,
      );
      expect(
        belts.where((b) => b.size == DesignConstants.rankBeltXSmall).length,
        4,
      );
      // Purple is the featured name, so it carries the strong ink label.
      final purple = tester.widget<Text>(find.text('Purple'));
      expect(purple.style?.fontSize, DesignConstants.kioskLabel.fontSize);
      final white = tester.widget<Text>(find.text('White'));
      expect(white.style?.fontSize, DesignConstants.kioskTag.fontSize);
      expect(white.style?.color, DesignConstants.text2nd);
    });

    testWidgets('the featured index is always the lower middle, so a belt '
        'above it always exists', (tester) async {
      // The rule itself — a bar that names "…to {next belt}" needs one.
      for (var count = 2; count <= 8; count++) {
        final index = kioskFeaturedRungIndex(count);
        expect(index, greaterThanOrEqualTo(0));
        expect(index, lessThan(count - 1), reason: 'count=$count');
      }
      expect(kioskFeaturedRungIndex(1), 0);
      expect(kioskFeaturedRungIndex(3), 1);
      expect(kioskFeaturedRungIndex(5), 2);
    });

    testWidgets('nothing claims the rung for the viewer', (tester) async {
      await pumpSlide(tester, [
        _rank('White', 1),
        _rank('Blue', 2),
        _rank('Purple', 3),
      ]);

      // The old member-linked tag is gone, and no second-person claim about
      // anybody's standing replaced it.
      expect(find.text('You\'re here'), findsNothing);
      expect(find.textContaining('You\'re'), findsNothing);
      expect(find.textContaining('Your'), findsNothing);
      expect(find.textContaining('your'), findsNothing);
      // The caption describes the FEATURE, not the reader's rank.
      expect(
        find.text('Every class you take counts toward the next belt.'),
        findsOneWidget,
      );
    });
  });

  group('the progress bar', () {
    testWidgets('renders a partly filled rail — never empty, never full',
        (tester) async {
      await pumpSlide(tester, [
        _rank('White', 1),
        _rank('Blue', 2),
        _rank('Purple', 3),
      ]);

      final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(bar.value, greaterThan(0));
      expect(bar.value, lessThan(1));
      expect(bar.minHeight, DesignConstants.kioskProgressBarThickness);
      expect(bar.color, DesignConstants.primaryColor);
    });

    testWidgets('the denominator is the gym\'s OWN threshold and the belt it '
        'names is the gym\'s next one', (tester) async {
      // White / Blue / Purple -> Blue is featured, Blue's own
      // classes_to_next_major is 30, and Purple is what comes next.
      await pumpSlide(tester, [
        _rank('White', 1),
        _rank('Blue', 2, classesToNextMajor: 30),
        _rank('Purple', 3),
      ]);

      expect(
        find.text('18 / 30 classes to Purple', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('a single-rung ladder names no next belt', (tester) async {
      await pumpSlide(tester, [_rank('White', 1, classesToNextMajor: 10)]);

      expect(find.text('6 / 10 classes', findRichText: true), findsOneWidget);
      expect(find.textContaining('to ', findRichText: true), findsNothing);
    });

    testWidgets('an unusable gym threshold falls back rather than showing a '
        'nonsense fraction', (tester) async {
      // Blue is the featured rung here, and the gym left its threshold at 0.
      await pumpSlide(tester, [
        _rank('White', 1),
        _rank('Blue', 2, classesToNextMajor: 0),
        _rank('Purple', 3),
      ]);

      expect(
        find.text('12 / 20 classes to Purple', findRichText: true),
        findsOneWidget,
      );
    });
  });

  group('it is safe and it fits', () {
    testWidgets('an empty ladder renders nothing at all', (tester) async {
      await pumpSlide(tester, const []);

      expect(tester.takeException(), isNull);
      expect(find.byType(RankBeltImage), findsNothing);
      expect(find.byType(KioskRankProgress), findsNothing);
    });

    testWidgets('a long ladder scrolls sideways only — it never overflows',
        (tester) async {
      await pumpSlide(
        tester,
        [for (var i = 1; i <= 10; i++) _rank('Belt $i', i)],
        surface: const Size(420, 420),
      );

      expect(tester.takeException(), isNull);
      for (final scrollable
          in tester.widgetList<Scrollable>(find.byType(Scrollable))) {
        expect(axisDirectionToAxis(scrollable.axisDirection), Axis.horizontal);
      }
    });
  });
}
