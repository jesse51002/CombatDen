import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_app/features/stats/data/reward_slide.dart';
import 'package:mobile_app/features/stats/data/rewards_card_view.dart';

/// A live catalog slide. The image never resolves in these tests — the view
/// model is pure data.
RewardSlide _live(String name, int cost) => RewardSlide(
      image: const AssetImage('reward.png'),
      name: name,
      discountLabel: 'Free',
      pointsCost: cost,
      isLive: true,
    );

/// A bundled fallback slide: same shape, DEMO cost.
RewardSlide _bundled(String name, int cost) => RewardSlide(
      image: const AssetImage('reward.png'),
      name: name,
      discountLabel: 'Free',
      pointsCost: cost,
      isLive: false,
    );

RewardsCardView _view(List<RewardSlide> slides, int? balance) =>
    buildRewardsCardView(slides: slides, pointsBalance: balance);

void main() {
  group('a slide states whether the member can have it', () {
    test('affordable is REDEEMABLE with a closed ring and a plain price', () {
      final view = _view([_live('Bring a friend', 800)], 800);
      final slide = view.slides.single;

      expect(slide.affordance, RewardAffordance.redeemable);
      expect(slide.progress, 1);
      expect(slide.valueLabel, '800 pts');
    });

    test('unaffordable is LOCKED, with the x / y points progress sentence', () {
      final view = _view([_live('Gym t-shirt', 2200)], 120);
      final slide = view.slides.single;

      expect(slide.affordance, RewardAffordance.locked);
      expect(slide.progress, closeTo(120 / 2200, 0.0001));
      // Thousand separators, both numbers, via the ONE public formatter.
      expect(slide.valueLabel, '120 / 2,200 points');
    });

    test('a free reward is redeemable even on a zero balance', () {
      final view = _view([_live('Water bottle', 0)], 0);

      expect(view.slides.single.affordance, RewardAffordance.redeemable);
    });

    test('a locked ring never overfills', () {
      final view = _view([_live('Seminar', 100)], 99);

      expect(view.slides.single.progress, lessThanOrEqualTo(1.0));
      expect(view.slides.single.progress, greaterThan(0.0));
    });
  });

  group('a balance we do not have is UNKNOWN, never zero', () {
    test('a null balance renders the shipped look, not a 0 / y shortfall', () {
      final view = _view([_live('Gym t-shirt', 2200)], null);
      final slide = view.slides.single;

      expect(slide.affordance, RewardAffordance.unknown);
      expect(slide.progress, 1);
      // Showing "0 / 2,200" to a member who may hold 3,000 points would be a
      // lie; the unknown branch states the price and nothing about the member.
      expect(slide.valueLabel, '2,200 pts');
      expect(slide.valueLabel, isNot(contains('/')));
    });

    test('bundled fallback slides are unknown WHATEVER the balance', () {
      // Their costs are demo numbers, so a shortfall measured against them
      // would be a shortfall that does not exist.
      final view = _view([_bundled('Gym t-shirt', 2200)], 120);

      expect(view.slides.single.affordance, RewardAffordance.unknown);
      expect(view.slides.single.valueLabel, '2,200 pts');
    });

    test('the unknown card keeps the neutral title and subtitle', () {
      final view = _view([_bundled('Gym t-shirt', 2200)], 120);

      expect(view.title, 'Rewards you can get');
      expect(view.subtitle, 'Swipe to view rewards');
      expect(view.featuredIndex, 0);
    });
  });

  group('the card opens on the strongest slide it can', () {
    test('with something affordable it features the most EXPENSIVE one', () {
      final view = _view(
        [_live('Cheap', 100), _live('Mid', 500), _live('Dear', 5000)],
        900,
      );

      expect(view.featuredIndex, 1);
      expect(view.slides[2].affordance, RewardAffordance.locked);
    });

    test('with nothing affordable it features the cheapest', () {
      final view = _view([_live('Cheap', 1000), _live('Dear', 5000)], 950);

      expect(view.featuredIndex, 0);
    });

    test('an empty catalog cannot throw', () {
      final view = _view(const [], 900);

      expect(view.slides, isEmpty);
      expect(view.featuredIndex, 0);
      expect(view.title, 'Rewards you can get');
    });
  });

  group('the title and subtitle are derived, not demo chrome', () {
    test('one affordable reward reads in the singular', () {
      final view = _view([_live('Cheap', 100), _live('Dear', 5000)], 900);

      expect(view.title, 'Rewards you can get');
      expect(view.subtitle, '1 reward ready to redeem');
    });

    test('several affordable rewards read in the plural', () {
      final view = _view([_live('A', 100), _live('B', 500)], 900);

      expect(view.subtitle, '2 rewards ready to redeem');
    });

    test('all locked leads with the DISTANCE, not a denial', () {
      final view = _view([_live('Cheap', 1000), _live('Dear', 5000)], 950);

      expect(view.title, 'Almost there');
      expect(view.subtitle, '50 points to go');
    });

    test('the gap is measured to the cheapest, in any order', () {
      final view = _view([_live('Dear', 5000), _live('Cheap', 2000)], 1000);

      expect(view.subtitle, '1,000 points to go');
    });
  });

  group('a one-reward catalog', () {
    test('resolves exactly as a longer one', () {
      final view = _view([_live('Only', 800)], 800);

      expect(view.slides, hasLength(1));
      expect(view.featuredIndex, 0);
      expect(view.subtitle, '1 reward ready to redeem');
    });
  });
}
