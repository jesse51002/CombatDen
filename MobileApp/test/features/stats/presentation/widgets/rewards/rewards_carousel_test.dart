import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/reward_card/reward_card.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/reward_card/reward_ready_tag.dart';
import 'package:mobile_app/features/stats/data/mock_stats.dart';
import 'package:mobile_app/features/stats/data/reward_slide.dart';
import 'package:mobile_app/features/stats/data/rewards_card_view.dart';
import 'package:mobile_app/features/stats/presentation/widgets/rewards/rewards_carousel.dart';

// The store frames a reward photo 3:2 (`RewardImageHero`); the celebration
// carousel has to agree, or the same upload is cropped two different ways.
const double _kAspect = 1.5;
const double _kFeaturedWidth = 208;

/// The bundled catalog, resolved with no balance — the UNKNOWN state, which is
/// byte-for-byte the look the card shipped before affordability existed.
final List<RewardsCardSlide> _unknownSlides = buildRewardsCardView(
  slides: [
    for (final item in mockRewardsStats.items) RewardSlide.fromMock(item),
  ],
  pointsBalance: null,
).slides;

RewardSlide _live(int cost) => RewardSlide(
      image: const AssetImage('reward.png'),
      name: 'Reward',
      discountLabel: 'Free',
      pointsCost: cost,
      isLive: true,
    );

/// One live slide resolved against [balance] — redeemable at or above cost,
/// locked below it.
List<RewardsCardSlide> _oneSlide({required int cost, required int balance}) =>
    buildRewardsCardView(
      slides: [_live(cost)],
      pointsBalance: balance,
    ).slides;

Widget _host(
  PageController controller, {
  List<RewardsCardSlide>? items,
}) =>
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: RewardsCarousel(
            items: items ?? _unknownSlides,
            controller: controller,
            onPageChanged: (_) {},
          ),
        ),
      ),
    );

/// The framed photo box of a slide — the first decorated container inside the
/// carousel (the two tags are Containers too, and sit above it in the stack).
Finder get _slideBox => find
    .descendant(
      of: find.byType(RewardsCarousel),
      matching: find.byType(Container),
    )
    .first;

BoxDecoration _slideDecoration(WidgetTester tester) =>
    tester.widget<Container>(_slideBox).decoration! as BoxDecoration;

/// Every slide's ring painter, in tree order.
List<CustomPainter> _ringPainters(WidgetTester tester) => tester
    .widgetList<CustomPaint>(
      find.descendant(
        of: find.byType(RewardsCarousel),
        matching: find.byType(CustomPaint),
      ),
    )
    .map((paint) => paint.foregroundPainter)
    .whereType<CustomPainter>()
    .toList();

void main() {
  late PageController controller;

  setUp(() {
    controller = PageController(initialPage: 1, viewportFraction: 0.45);
  });
  tearDown(() => controller.dispose());

  group('the reward slide frames a rectangular upload', () {
    testWidgets('is a rounded RECTANGLE, never a circle', (tester) async {
      await tester.pumpWidget(_host(controller));

      final decoration = _slideDecoration(tester);
      expect(decoration.shape, BoxShape.rectangle);
      expect(
        decoration.borderRadius,
        BorderRadius.circular(DesignConstants.radiusBig),
      );
    });

    testWidgets('keeps the clipped, covered photo it always had',
        (tester) async {
      await tester.pumpWidget(_host(controller));

      // The frame moved from `BoxDecoration.border` onto the ring painter, so
      // the same band can carry progress. The photo container no longer draws
      // its own outline.
      expect(_slideDecoration(tester).border, isNull);
      expect(_ringPainters(tester), isNotEmpty);
      expect(tester.widget<Container>(_slideBox).clipBehavior, Clip.antiAlias);

      final image = tester.widget<Image>(
        find
            .descendant(of: _slideBox, matching: find.byType(Image))
            .first,
      );
      expect(image.fit, BoxFit.cover);
      expect(image.errorBuilder, isNotNull);
    });

    testWidgets('is 3:2 at the featured width, and the carousel reserves it',
        (tester) async {
      await tester.pumpWidget(_host(controller));

      final box = tester.getSize(_slideBox);
      expect(box.width, closeTo(_kFeaturedWidth, 0.01));
      expect(box.width / box.height, closeTo(_kAspect, 0.001));

      // The row's own height follows the slide, so the card's stack doesn't
      // reserve a square's worth of room for a 3:2 photo.
      expect(
        tester.getSize(find.byType(RewardsCarousel)).height,
        closeTo(box.height, 0.01),
      );
    });

    testWidgets('every slide carries the store\'s price tag', (tester) async {
      await tester.pumpWidget(_host(controller));

      expect(find.byType(RewardPriceTag), findsWidgets);
    });
  });

  group('the slide says which rewards the member can actually get', () {
    testWidgets('a redeemable slide is tagged READY', (tester) async {
      await tester.pumpWidget(
        _host(controller, items: _oneSlide(cost: 800, balance: 800)),
      );

      expect(find.byType(RewardReadyTag), findsWidgets);
      expect(find.text('Ready'), findsWidgets);
    });

    testWidgets('a locked slide carries no tag — absence IS the signal',
        (tester) async {
      await tester.pumpWidget(
        _host(controller, items: _oneSlide(cost: 2200, balance: 120)),
      );

      expect(find.byType(RewardReadyTag), findsNothing);
      // It still shows what it costs.
      expect(find.byType(RewardPriceTag), findsWidgets);
    });

    testWidgets('an unknown slide carries no tag either', (tester) async {
      await tester.pumpWidget(_host(controller));

      expect(find.byType(RewardReadyTag), findsNothing);
    });

    testWidgets('the ring is painted DIFFERENTLY for the two states',
        (tester) async {
      await tester.pumpWidget(
        _host(controller, items: _oneSlide(cost: 800, balance: 800)),
      );
      final redeemable = _ringPainters(tester).first;
      // Same state, same paint — the ring doesn't repaint on a rebuild.
      expect(redeemable.shouldRepaint(_ringPainters(tester).last), isFalse);

      await tester.pumpWidget(
        _host(controller, items: _oneSlide(cost: 2200, balance: 120)),
      );
      final locked = _ringPainters(tester).first;

      // Closed accent ring vs. a partial `text` stroke over a hairline track.
      expect(locked.shouldRepaint(redeemable), isTrue);
    });
  });
}
