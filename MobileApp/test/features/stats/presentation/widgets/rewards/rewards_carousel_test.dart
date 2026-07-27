import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/stats/data/mock_stats.dart';
import 'package:mobile_app/features/stats/presentation/widgets/rewards/reward_slide.dart';
import 'package:mobile_app/features/stats/presentation/widgets/rewards/rewards_carousel.dart';

// The store frames a reward photo 3:2 (`RewardImageHero`); the celebration
// carousel has to agree, or the same upload is cropped two different ways.
const double _kAspect = 1.5;
const double _kFeaturedWidth = 208;

final List<RewardSlide> _slides = [
  for (final item in mockRewardsStats.items) RewardSlide.fromMock(item),
];

Widget _host(PageController controller) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: RewardsCarousel(
            items: _slides,
            controller: controller,
            onPageChanged: (_) {},
          ),
        ),
      ),
    );

/// The framed photo box of a slide — the carousel's only decorated container.
Finder get _slideBox => find
    .descendant(
      of: find.byType(RewardsCarousel),
      matching: find.byType(Container),
    )
    .first;

BoxDecoration _slideDecoration(WidgetTester tester) =>
    tester.widget<Container>(_slideBox).decoration! as BoxDecoration;

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

    testWidgets('keeps the outlined, clipped frame it always had',
        (tester) async {
      await tester.pumpWidget(_host(controller));

      final border = _slideDecoration(tester).border! as Border;
      expect(border.top.color, DesignConstants.text);
      expect(border.top.width, DesignConstants.buttonBorderSize);
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
  });
}
