import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_app/features/profile/data/models/member_promotion.dart';
import 'package:mobile_app/features/stats/presentation/widgets/promotion/promotion_body.dart';
import 'package:mobile_app/shared/widgets/animation/sparkle_burst.dart';
import 'package:mobile_app/shared/widgets/post_class/post_class_controller.dart';
import 'package:mobile_app/shared/widgets/rank/rank_belt_image.dart';

MemberPromotion _promotion({
  String? oldRankName = 'Blue Belt · 2 Stripes',
  String? newRankName = 'Purple Belt',
  String? oldImageUrl = 'https://cdn.test/blue.png',
  String? newImageUrl = 'https://cdn.test/purple.png',
}) =>
    MemberPromotion(
      activityId: 'act-1',
      promotedAt: DateTime.utc(2026, 7, 25, 12),
      oldRankName: oldRankName,
      newRankName: newRankName,
      oldImageUrl: oldImageUrl,
      newImageUrl: newImageUrl,
    );

void _phoneSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Future<void> _pump(
  WidgetTester tester,
  MemberPromotion promotion, {
  PostClassController? controller,
}) async {
  _phoneSurface(tester);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: PromotionBody(promotion: promotion, controller: controller),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 16));
}

final Finder _belts = find.descendant(
  of: find.byType(PromotionBody),
  matching: find.byType(RankBeltImage),
);

void main() {
  group('the belt is one object whose identity changes', () {
    testWidgets('both sides are rendered, and they cross-dissolve',
        (tester) async {
      await _pump(tester, _promotion());

      // Two sides, co-located — never a swap for a different widget.
      expect(_belts, findsNWidgets(2));
      final urls = tester
          .widgetList<RankBeltImage>(_belts)
          .map((b) => b.imageUrl)
          .toList();
      expect(urls, ['https://cdn.test/blue.png', 'https://cdn.test/purple.png']);

      await tester.pumpAndSettle();
    });

    testWidgets('the belt lands in the 154 x 100 slot', (tester) async {
      await _pump(tester, _promotion());
      final entranceSize = tester.getSize(_belts.first);
      expect(entranceSize.width, greaterThan(154));

      await tester.pumpAndSettle();

      // 2x RankHeader's 77 x 50 — same aspect, obvious provenance, and not a
      // thumbnail to end a belt celebration on.
      final landed = tester.getSize(_belts.first);
      expect(landed.width, closeTo(154, 0.01));
      expect(landed.height, closeTo(100, 0.01));
    });

    testWidgets('the settled frame states the change in full', (tester) async {
      await _pump(tester, _promotion());
      await tester.pumpAndSettle();

      expect(find.text("YOU'VE BEEN PROMOTED"), findsOneWidget);
      expect(find.text('Purple Belt'), findsOneWidget);
      expect(find.text('from Blue Belt · 2 Stripes'), findsOneWidget);
    });
  });

  group('a FIRST assignment is an arrival, not a transition', () {
    testWidgets('one belt, its own copy, and no "from" line', (tester) async {
      await _pump(
        tester,
        _promotion(oldRankName: null, oldImageUrl: null),
      );

      // Nothing to animate FROM, so the from-belt is not built — not built
      // and hidden, not built.
      expect(_belts, findsOneWidget);
      expect(
        tester.widget<RankBeltImage>(_belts).imageUrl,
        'https://cdn.test/purple.png',
      );

      await tester.pumpAndSettle();

      // "Promoted" with no "from" reads as a missing sentence to a white belt
      // on day one, and this is the MOST COMMON state at a new gym.
      expect(find.text('YOUR FIRST RANK'), findsOneWidget);
      expect(find.text("YOU'VE BEEN PROMOTED"), findsNothing);
      expect(find.textContaining('from '), findsNothing);
      expect(find.text('Purple Belt'), findsOneWidget);
    });

    testWidgets('it settles sooner than a full promotion', (tester) async {
      final controller = PostClassController();
      await _pump(
        tester,
        _promotion(oldRankName: null, oldImageUrl: null),
        controller: controller,
      );
      // Enter 420 + admire 620 + settle 700 = 1,740ms; the hold and the swap
      // are dropped, so the full 2,660ms timeline would still be running.
      await tester.pump(const Duration(milliseconds: 1800));
      expect(controller.isAnimating, isFalse);

      await tester.pumpAndSettle();
    });
  });

  group('a LEGACY row still reads, with no art at all', () {
    testWidgets('both sides fall back to the themed belt and the words carry it',
        (tester) async {
      await _pump(
        tester,
        _promotion(oldImageUrl: null, newImageUrl: null),
      );

      // Two sides still, both resolving to the themed/bundled mark: the
      // dissolve is a visual no-op and the NAME, the swell and the sparkles
      // carry the beat. No "legacy mode" branch exists.
      expect(_belts, findsNWidgets(2));
      for (final belt in tester.widgetList<Image>(
        find.descendant(of: _belts.first, matching: find.byType(Image)),
      )) {
        expect(belt.image, isNot(isA<CachedNetworkImageProvider>()));
      }

      await tester.pumpAndSettle();
      expect(find.text("YOU'VE BEEN PROMOTED"), findsOneWidget);
      expect(find.text('Purple Belt'), findsOneWidget);
      expect(find.text('from Blue Belt · 2 Stripes'), findsOneWidget);
    });

    testWidgets('identical URLs still exit the old NAME upward',
        (tester) async {
      // A stripe promotion with no per-sub override paints one picture, so the
      // name is the signal that survives.
      const url = 'https://cdn.test/blue.png';
      final promotion = _promotion(oldImageUrl: url, newImageUrl: url);
      expect(promotion.beltArtUnchanged, isTrue);
      await _pump(tester, promotion);

      // Mid-enter: the old name is on screen, at full-ish opacity.
      await tester.pump(const Duration(milliseconds: 400));
      final label = find.text('Blue Belt · 2 Stripes');
      expect(label, findsOneWidget);
      final before = tester.getCenter(label);

      // Mid-swap: it has faded and translated UP — the member moved up.
      await tester.pump(const Duration(milliseconds: 1160));
      final after = tester.getCenter(label);
      expect(after.dy, lessThan(before.dy));

      await tester.pumpAndSettle();
    });
  });

  testWidgets('a belt that fails to load falls back rather than leaving a hole',
      (tester) async {
    await _pump(tester, _promotion());
    final image = tester.widget<Image>(
      find.descendant(of: _belts.last, matching: find.byType(Image)),
    );
    expect(image.errorBuilder, isNotNull);
    final onError = image.errorBuilder!(
      tester.element(_belts.last),
      Exception('404'),
      StackTrace.empty,
    );
    await tester.pumpAndSettle();

    await tester.pumpWidget(MaterialApp(home: Scaffold(body: onError)));
    final fallback = tester.widget<Image>(find.byType(Image));
    expect(fallback.image, isNot(isA<CachedNetworkImageProvider>()));
    expect(fallback.fit, BoxFit.contain);
  });

  group('the skip is genuinely instant', () {
    testWidgets('a tap lands the final frame and releases the CTA',
        (tester) async {
      final controller = PostClassController();
      await _pump(tester, _promotion(), controller: controller);
      expect(controller.isAnimating, isTrue);

      controller.requestSkip();
      await tester.pump();

      expect(controller.isAnimating, isFalse);
      // Final frame, in full — nothing here is a self-driving child that a
      // jump could not fast-forward.
      final landed = tester.getSize(_belts.first);
      expect(landed.width, closeTo(154, 0.01));
      expect(find.text("YOU'VE BEEN PROMOTED"), findsOneWidget);
      expect(find.text('from Blue Belt · 2 Stripes'), findsOneWidget);

      await tester.pumpAndSettle();
    });

    testWidgets('a skip never STARTS a sparkle scatter', (tester) async {
      final controller = PostClassController();
      await _pump(tester, _promotion(), controller: controller);
      // Before the swap beat: no burst yet.
      expect(find.byType(SparkleBurst), findsNothing);

      controller.requestSkip();
      await tester.pump();

      // A scatter that BEGINS animating after a skip is the opposite of what
      // was asked for, so it is suppressed rather than fast-forwarded.
      expect(find.byType(SparkleBurst), findsNothing);

      await tester.pumpAndSettle();
    });

    testWidgets('left alone, the swap beat DOES fire the sparkles',
        (tester) async {
      await _pump(tester, _promotion());
      expect(find.byType(SparkleBurst), findsNothing);

      // Enter 420 + hold 560 = 980ms in, the swap starts.
      await tester.pump(const Duration(milliseconds: 1000));
      expect(find.byType(SparkleBurst), findsOneWidget);

      await tester.pumpAndSettle();
    });
  });
}
