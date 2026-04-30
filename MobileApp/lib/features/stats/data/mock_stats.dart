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
    required this.amountLabel,
    required this.heroAsset,
  });

  final String amountLabel;
  final String heroAsset;
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
    required this.progressFraction,
    required this.previousProgressFraction,
    required this.nextTierLabel,
    required this.classesAttended,
    required this.classesRequired,
  });

  final String rankTitle;
  final String rankSubtitle;
  final String beltAsset;

  /// Total progress to the next tier (0..1), including the new gain.
  final double progressFraction;

  /// Progress before this class — visualized as the dimmer band of the bar.
  final double previousProgressFraction;
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
  subtitle: 'Every session you get stronger',
  heroAsset: 'stat_wins_trophy.png',
  tiles: [
    MockWinTile(iconName: 'star', value: '3 week', label: 'Streak'),
    MockWinTile(iconName: 'award', value: '+50', label: 'Rating'),
    MockWinTile(iconName: 'gift', value: '+160', label: 'Points'),
  ],
);

const mockPointsStats = MockPointsStats(
  amountLabel: '+160 points',
  heroAsset: 'stat_points_stars.png',
);

const mockRewardsStats = MockRewardsStats(
  title: 'Rewards You Can Get',
  subtitle: 'Swipe to view rewards',
  featuredIndex: 1,
  items: [
    MockRewardItem(
      imageAsset: 'stat_reward_wraps.png',
      name: 'Hand Wraps',
      discountLabel: '\$10 off',
      pointsCost: 1500,
    ),
    MockRewardItem(
      imageAsset: 'stat_reward_gloves.png',
      name: 'Venom Boxing Gloves',
      discountLabel: '\$20 off',
      pointsCost: 2200,
    ),
    MockRewardItem(
      imageAsset: 'stat_reward_shirt.png',
      name: 'Muay Thai Tee',
      discountLabel: '\$15 off',
      pointsCost: 2500,
    ),
  ],
);

const mockRankStats = MockRankStats(
  rankTitle: 'Gold Belt',
  rankSubtitle: 'Stripe III',
  beltAsset: 'stat_rank_belt.png',
  progressFraction: 0.55,
  previousProgressFraction: 0.32,
  nextTierLabel: 'Silver I',
  classesAttended: 28,
  classesRequired: 50,
);
