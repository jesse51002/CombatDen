import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_app/features/stats/data/reward_slide.dart';
import 'package:mobile_app/features/stats/data/rewards_card_view.dart';
import 'package:mobile_app/features/stats/presentation/widgets/rewards/rewards_body.dart';
import 'package:mobile_app/features/stats/presentation/widgets/rewards/rewards_carousel.dart';
import 'package:mobile_app/shared/widgets/post_class/post_class_controller.dart';

RewardSlide _slide(String name, int cost) => RewardSlide(
      image: const AssetImage('assets/rewards/reward_gloves.png'),
      name: name,
      discountLabel: 'Free',
      pointsCost: cost,
      isLive: true,
    );

RewardsCardView _view(int count) => buildRewardsCardView(
      slides: [
        for (var i = 0; i < count; i++) _slide('Reward $i', 100 * (i + 1)),
      ],
      pointsBalance: 10000,
    );

/// Mounts the card and jumps past the giftbox intro the way a member tapping
/// the screen does, so the assertions are about the settled carousel.
Future<RewardsCarousel> _pumpSettled(
  WidgetTester tester,
  RewardsCardView view,
) async {
  final controller = PostClassController();
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: RewardsBody(view: view, controller: controller),
      ),
    ),
  );
  controller.requestSkip();
  await tester.pump();
  return tester.widget<RewardsCarousel>(find.byType(RewardsCarousel));
}

/// Tear the tree down inside the test, then flush: disposing cancels the
/// advance timer, and the extra pump lets the reveals' delayed callbacks fire
/// against an unmounted tree instead of outliving the test.
Future<void> _teardownTree(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  group('a ONE-reward catalog has nowhere to go, so it does not go', () {
    testWidgets('never auto-advances from a photo to the identical photo',
        (tester) async {
      final carousel = await _pumpSettled(tester, _view(1));
      final before = carousel.controller.page;
      expect(before, isNotNull);

      // Well past the 5s idle delay and the 450ms slide it would animate.
      await tester.pump(const Duration(seconds: 6));
      await tester.pump(const Duration(milliseconds: 500));

      expect(carousel.controller.page, closeTo(before!, 0.001));

      await _teardownTree(tester);
    });

    testWidgets('refuses the swipe too — there is no second slide',
        (tester) async {
      final carousel = await _pumpSettled(tester, _view(1));

      expect(carousel.physics, isA<NeverScrollableScrollPhysics>());

      await _teardownTree(tester);
    });
  });

  group('a real catalog still rotates', () {
    testWidgets('advances one slide after the idle delay', (tester) async {
      final carousel = await _pumpSettled(tester, _view(3));
      final before = carousel.controller.page!;

      await tester.pump(const Duration(seconds: 6));
      await tester.pump(const Duration(milliseconds: 500));

      expect(carousel.controller.page, closeTo(before + 1, 0.01));

      await _teardownTree(tester);
    });

    testWidgets('is swipeable', (tester) async {
      final carousel = await _pumpSettled(tester, _view(3));

      expect(carousel.physics, isA<BouncingScrollPhysics>());

      await _teardownTree(tester);
    });
  });

  group('an empty catalog is a developer error, and a loud one', () {
    testWidgets('trips the assert rather than dividing by zero',
        (tester) async {
      // The screen can never hand one over — it falls back to the bundled
      // catalog — and `_initialPageBase % 0` would throw if it did. `build`
      // carries the same guard for release mode.
      final controller = PostClassController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RewardsBody(
              view: buildRewardsCardView(slides: const [], pointsBalance: 0),
              controller: controller,
            ),
          ),
        ),
      );

      expect(tester.takeException(), isAssertionError);

      await _teardownTree(tester);
    });
  });
}
