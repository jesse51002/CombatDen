import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/stub_asset_bundle.dart';

import 'package:mobile_app/core/formats/layout_formats.dart';
import 'package:mobile_app/features/rewards/data/reward.dart';
import 'package:mobile_app/features/rewards/presentation/layouts/rewards_layout.dart';
import 'package:mobile_app/features/rewards/presentation/layouts/rewards_layout_data.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/points_headline.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/reward_card/parts/reward_image_hero.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/reward_card/parts/reward_points_cost.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/reward_card/parts/reward_price_tag.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/reward_card/parts/reward_title.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/reward_card/reward_card.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/reward_card/reward_redeem_dialog.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/rewards_load_status.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/rewards_tabs/rewards_tabs.dart';
import 'package:mobile_app/shared/widgets/buttons/app_primary_button.dart';
import 'package:mobile_app/shared/widgets/nav/app_bottom_nav_bar.dart';
import 'package:mobile_app/shared/widgets/nav/app_nav_item.dart';
import 'package:mobile_app/shared/widgets/topbar/app_topbar.dart';

/// The functional-equivalence gate for `rewards_format`.
///
/// A layout format may change ARRANGEMENT ONLY. This asserts it
/// mechanically: every value of the enum is pumped with the same
/// fabricated store and its element set is compared against the
/// contract below. A generated layout that loses a reward, drops a
/// price tag, hands one card's redeem action to another, or quietly
/// stops showing the load status fails here rather than in review.
///
/// The rewards are LIVE data in the app; nothing here touches the
/// network. The payload is fabricated and handed straight to the layout,
/// which is the same seam `formatOverride` opens for the format.
void main() {
  const totalPoints = 3400;

  /// Deliberately awkward: a title far past the card's two-line clamp,
  /// a wide price label, and costs that straddle the member's balance so
  /// the price ladder produces all three of its bands.
  const rewards = <Reward>[
    Reward(
      title: 'Free Week',
      imageUrl: 'https://example.test/free-week.png',
      priceLabel: 'Free',
      pointsCost: 800,
    ),
    Reward(
      title: 'Limited edition championship rash guard with the gym '
          'crest embroidered across both shoulders',
      imageUrl: 'https://example.test/rash-guard.png',
      priceLabel: '30% off',
      pointsCost: 1200,
    ),
    Reward(
      title: 'Private Coaching Hour',
      imageUrl: 'https://example.test/private.png',
      priceLabel: 'Free',
      pointsCost: 3400,
    ),
    Reward(
      title: 'Gym Duffel Bag',
      imageUrl: 'https://example.test/duffel.png',
      priceLabel: '50% off',
      pointsCost: 6800,
    ),
    Reward(
      title: 'Annual Membership',
      imageUrl: 'https://example.test/annual.png',
      priceLabel: 'Free',
      pointsCost: 20000,
    ),
  ];

  RewardsLayoutData data({
    List<Reward> items = rewards,
    bool isLoading = false,
    String? statusMessage,
  }) {
    return RewardsLayoutData(
      gymName: 'Global MMA',
      logoAsset: 'gym_logo_global_mma.png',
      streakDays: 3,
      pointsLabel: '3.4k',
      rankBadgeAsset: 'icon_rank_belt.png',
      totalPoints: totalPoints,
      rewards: items,
      isLoading: isLoading,
      statusMessage: statusMessage,
    );
  }

  /// Pump at a real phone size. At the default 800x600 test surface a
  /// cramped arrangement still fits, so a layout that overflows on an
  /// actual device would pass unnoticed.
  void phoneSized(WidgetTester tester) {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
  }

  Widget host(RewardsFormat format, RewardsLayoutData payload) {
    return withStubAssets(
      MaterialApp(
        home: RewardsLayout(data: payload, formatOverride: format),
      ),
    );
  }

  /// The chrome every format carries in every state.
  void expectChrome() {
    expect(find.byType(AppTopbar), findsOneWidget);
    expect(find.byType(RewardsTabs), findsOneWidget);
    expect(find.text('Points Store'), findsOneWidget);
    expect(find.text('My Rewards'), findsOneWidget);
    expect(find.byType(PointsHeadline), findsOneWidget);
    expect(find.byType(AppBottomNavBar), findsOneWidget);
    expect(find.byType(AppNavItem), findsNWidgets(4));
  }

  group('every rewards format renders the whole store', () {
    for (final format in RewardsFormat.values) {
      testWidgets('$format', (tester) async {
        phoneSized(tester);
        await tester.pumpWidget(host(format, data()));
        await tester.pump();

        expectChrome();
        // The store is loaded, so the status chrome stands down.
        expect(find.byType(RewardsLoadStatus), findsNothing);

        // One card per reward — none dropped, none duplicated.
        final cards = find.byType(RewardCard);
        expect(cards, findsNWidgets(rewards.length));
        for (final reward in rewards) {
          expect(find.text(reward.title), findsOneWidget);
        }
      });
    }
  });

  group('every card carries every element, in every format', () {
    for (final format in RewardsFormat.values) {
      testWidgets('$format', (tester) async {
        phoneSized(tester);
        await tester.pumpWidget(host(format, data()));
        await tester.pump();

        final cards = find.byType(RewardCard);
        for (var i = 0; i < rewards.length; i++) {
          final card = cards.at(i);
          Finder inCard(Finder matching) =>
              find.descendant(of: card, matching: matching);

          expect(inCard(find.byType(RewardImageHero)), findsOneWidget);
          expect(inCard(find.byType(RewardPriceTag)), findsOneWidget);
          expect(inCard(find.byType(RewardTitle)), findsOneWidget);
          expect(inCard(find.byType(RewardPointsCost)), findsOneWidget);

          // Exactly one redeem action, and it belongs to THIS card.
          // A layout that lifts the action out to one screen-level
          // button fails here, which is the intent: the count per
          // reward is the contract, and it is checked per reward.
          final action = inCard(find.byType(AppPrimaryButton));
          expect(action, findsOneWidget);
          final button = tester.widget<AppPrimaryButton>(action);
          expect(button.text, 'Redeem');
          expect(button.onPressed, isNotNull);
        }
      });
    }
  });

  group('the redeem action still redeems, in every format', () {
    for (final format in RewardsFormat.values) {
      testWidgets('$format', (tester) async {
        phoneSized(tester);
        await tester.pumpWidget(host(format, data()));
        await tester.pump();

        final action = find.descendant(
          of: find.byType(RewardCard).first,
          matching: find.byType(AppPrimaryButton),
        );
        await tester.ensureVisible(action);
        await tester.pump();
        await tester.tap(action);
        await tester.pump();

        expect(find.byType(RewardRedeemDialog), findsOneWidget);
      });
    }
  });

  group('every format keeps the load status in every state', () {
    final states = <String, RewardsLayoutData>{
      'loading': data(items: const [], isLoading: true),
      'error': data(
        items: const [],
        statusMessage: 'Could not reach the video service.',
      ),
      'empty': data(
        items: const [],
        statusMessage: 'No rewards in the store yet.',
      ),
    };

    for (final format in RewardsFormat.values) {
      for (final entry in states.entries) {
        testWidgets('$format / ${entry.key}', (tester) async {
          phoneSized(tester);
          await tester.pumpWidget(host(format, entry.value));
          await tester.pump();

          expectChrome();
          expect(find.byType(RewardsLoadStatus), findsOneWidget);
          expect(find.byType(RewardCard), findsNothing);
        });
      }
    }
  });

  group('a one-reward store still shows that reward once', () {
    // storefrontHero promotes the first reward out of the grid; with a
    // single reward the grid is empty and the hero must not be a copy.
    for (final format in RewardsFormat.values) {
      testWidgets('$format', (tester) async {
        phoneSized(tester);
        await tester.pumpWidget(
          host(format, data(items: rewards.take(1).toList())),
        );
        await tester.pump();

        expectChrome();
        expect(find.byType(RewardCard), findsOneWidget);
        expect(find.text(rewards.first.title), findsOneWidget);
      });
    }
  });
}
