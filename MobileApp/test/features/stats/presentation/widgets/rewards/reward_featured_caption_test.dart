import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/stats/data/reward_slide.dart';
import 'package:mobile_app/features/stats/data/rewards_card_view.dart';
import 'package:mobile_app/features/stats/presentation/widgets/rewards/reward_featured_caption.dart';

RewardSlide _slide({required int cost, required bool isLive}) => RewardSlide(
      image: const AssetImage('assets/rewards/reward_mma_tshirt.png'),
      name: 'Gym t-shirt',
      discountLabel: 'Free',
      pointsCost: cost,
      isLive: isLive,
    );

Future<void> _pumpCaption(
  WidgetTester tester, {
  required int cost,
  required int? balance,
  bool isLive = true,
}) async {
  final view = buildRewardsCardView(
    slides: [_slide(cost: cost, isLive: isLive)],
    pointsBalance: balance,
  );
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: RewardFeaturedCaption(slide: view.slides.single, featuredIndex: 0),
      ),
    ),
  );
  await tester.pump();
}

Size _captionSize(WidgetTester tester) =>
    tester.getSize(find.byType(RewardFeaturedCaption));

void main() {
  group('the caption says what the member can DO', () {
    testWidgets('affordable: the price, plus a Ready to redeem line',
        (tester) async {
      await _pumpCaption(tester, cost: 800, balance: 900);

      expect(find.text('Gym t-shirt'), findsOneWidget);
      expect(find.text('800 pts'), findsOneWidget);
      expect(find.text('Ready to redeem'), findsOneWidget);
    });

    testWidgets('unaffordable: the x / y points progress sentence',
        (tester) async {
      await _pumpCaption(tester, cost: 2200, balance: 120);

      expect(find.text('120 / 2,200 points'), findsOneWidget);
      // A shortfall is not a celebration beat.
      expect(find.text('Ready to redeem'), findsNothing);
    });

    testWidgets('the shortfall is quiet type, not the orange headline',
        (tester) async {
      await _pumpCaption(tester, cost: 2200, balance: 120);

      final style = tester.widget<Text>(find.text('120 / 2,200 points')).style;
      expect(style?.color, DesignConstants.text2nd);
      expect(style?.color, isNot(DesignConstants.primaryColor));
    });
  });

  group('an unknown balance never states a shortfall', () {
    testWidgets('a null balance renders the price, not 0 / y', (tester) async {
      await _pumpCaption(tester, cost: 2200, balance: null);

      expect(find.text('2,200 pts'), findsOneWidget);
      expect(find.text('0 / 2,200 points'), findsNothing);
      expect(find.text('Ready to redeem'), findsNothing);
    });

    testWidgets('a bundled DEMO slide does the same on a real balance',
        (tester) async {
      await _pumpCaption(tester, cost: 2200, balance: 120, isLive: false);

      expect(find.text('2,200 pts'), findsOneWidget);
      expect(find.text('120 / 2,200 points'), findsNothing);
    });
  });

  group('the caption is height-reserved so an advance cannot shift the stack',
      () {
    testWidgets('every affordance renders the SAME caption height',
        (tester) async {
      await _pumpCaption(tester, cost: 800, balance: 900);
      final redeemable = _captionSize(tester).height;

      await _pumpCaption(tester, cost: 2200, balance: 120);
      final locked = _captionSize(tester).height;

      await _pumpCaption(tester, cost: 2200, balance: null);
      final unknown = _captionSize(tester).height;

      expect(locked, redeemable);
      expect(unknown, redeemable);
    });
  });
}
