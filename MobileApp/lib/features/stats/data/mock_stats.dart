import 'package:mobile_app/core/branding/brand.dart';

/// Hardcoded post-class celebration data. Visual prototype only —
/// every value here is shown verbatim on a stat card.
class MockStreakStats {
  const MockStreakStats({
    required this.weekCount,
    required this.subtitle,
    required this.weekDays,
  });

  final int weekCount;
  final String subtitle;
  final List<MockStreakDay> weekDays;
}

class MockStreakDay {
  const MockStreakDay({required this.label, required this.completed});

  final String label;
  final bool completed;
}

class MockWinTile {
  const MockWinTile({
    required this.iconName,
    required this.value,
    required this.label,
  });

  /// One of: `'star'`, `'award'`, `'gift'`. Mapped to a Material Symbol in
  /// the widget. Stored as a string so it survives a future JSON round-trip.
  final String iconName;
  final String value;
  final String label;
}

class MockWinsStats {
  const MockWinsStats({
    required this.title,
    required this.subtitle,
    required this.heroAsset,
    required this.tiles,
  });

  final String title;
  final String subtitle;
  final String heroAsset;
  final List<MockWinTile> tiles;
}

class MockPointsStats {
  const MockPointsStats({
    required this.gained,
    required this.totalPoints,
  });

  /// Points earned from this class — rolls 0 → [gained] in the count-up.
  final int gained;

  /// Member's all-time total points balance, shown in the small caption
  /// pinned at the bottom of the points screen.
  final int totalPoints;
}

class MockRewardItem {
  const MockRewardItem({
    required this.imageAsset,
    required this.name,
    required this.discountLabel,
    required this.pointsCost,
  });

  final String imageAsset;
  final String name;
  final String discountLabel;
  final int pointsCost;
}

class MockRewardsStats {
  const MockRewardsStats({
    required this.title,
    required this.subtitle,
    required this.featuredIndex,
    required this.items,
  });

  final String title;
  final String subtitle;
  final int featuredIndex;
  final List<MockRewardItem> items;
}

class MockRankStats {
  const MockRankStats({
    required this.rankTitle,
    required this.rankSubtitle,
    required this.beltAsset,
    required this.nextTierLabel,
    required this.classesAttended,
    required this.classesRequired,
  });

  final String rankTitle;
  final String rankSubtitle;
  final String beltAsset;
  final String nextTierLabel;

  final int classesAttended;
  final int classesRequired;
}

const mockStreakStats = MockStreakStats(
  weekCount: 3,
  subtitle: 'Completed your 2nd class this week',
  weekDays: [
    MockStreakDay(label: 'S', completed: false),
    MockStreakDay(label: 'M', completed: true),
    MockStreakDay(label: 'T', completed: false),
    MockStreakDay(label: 'W', completed: false),
    MockStreakDay(label: 'T', completed: true),
    MockStreakDay(label: 'F', completed: false),
    MockStreakDay(label: 'S', completed: false),
  ],
);

const mockWinsStats = MockWinsStats(
  title: 'Today’s wins',
  subtitle: 'The grind never stops',
  heroAsset: 'stat_wins_trophy.png',
  tiles: [
    MockWinTile(iconName: 'star', value: '3 week', label: 'Streak'),
    MockWinTile(iconName: 'award', value: '28', label: 'Rank Classes'),
    MockWinTile(iconName: 'gift', value: '+160', label: 'Points'),
  ],
);

const mockPointsStats = MockPointsStats(
  gained: 160,
  totalPoints: 3400,
);

const mockRewardsStats = MockRewardsStats(
  title: 'Rewards You Can Get',
  subtitle: 'Swipe to view rewards',
  featuredIndex: 1,
  items: [
    MockRewardItem(
      imageAsset: 'reward_bring_friend.png',
      name: 'Bring a friend',
      discountLabel: 'Free',
      pointsCost: 800,
    ),
    MockRewardItem(
      imageAsset: 'reward_mma_tshirt.png',
      name: 'Gym t-shirt',
      discountLabel: 'Free',
      pointsCost: 2200,
    ),
    MockRewardItem(
      imageAsset: 'reward_private_training.png',
      name: 'Private Training',
      discountLabel: '50% off',
      pointsCost: 3500,
    ),
  ],
);

const mockRankStats = MockRankStats(
  rankTitle: 'Gold Belt',
  rankSubtitle: 'Stripe III',
  beltAsset: 'stat_rank_belt.png',
  nextTierLabel: 'Gold Belt Stripe IV',
  classesAttended: 28,
  classesRequired: 50,
);

const mockRankStatsBjj = MockRankStats(
  rankTitle: 'Blue Belt',
  rankSubtitle: 'Stripe II',
  beltAsset: 'stat_rank_belt.png',
  nextTierLabel: 'Blue Belt Stripe III',
  classesAttended: 28,
  classesRequired: 50,
);

MockRankStats mockRankStatsFor(Brand brand) => switch (brand) {
  Brand.combatDen => mockRankStats,
  Brand.combatDenBjj => mockRankStatsBjj,
};
