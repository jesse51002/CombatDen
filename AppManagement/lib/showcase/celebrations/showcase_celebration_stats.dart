// Hardcoded post-class celebration data for the showcase island — clones of
// MobileApp's `mock_stats.dart` mock models + const values, kept verbatim so
// the showcase reads identically to the member app. Visual prototype only.

class ShowcaseWinTile {
  const ShowcaseWinTile({
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

class ShowcaseWinsStats {
  const ShowcaseWinsStats({
    required this.title,
    required this.subtitle,
    required this.heroAsset,
    required this.tiles,
  });

  final String title;
  final String subtitle;
  final String heroAsset;
  final List<ShowcaseWinTile> tiles;
}

class ShowcasePointsStats {
  const ShowcasePointsStats({
    required this.gained,
    required this.totalPoints,
  });

  /// Points earned from this class — rolls 0 → [gained] in the count-up.
  final int gained;

  /// Member's all-time total points balance, shown in the small caption
  /// pinned at the bottom of the points screen.
  final int totalPoints;
}

class ShowcaseRewardItem {
  const ShowcaseRewardItem({
    this.imageUrl,
    required this.imageAsset,
    required this.name,
    required this.discountLabel,
    required this.pointsCost,
  });

  /// Network image (the injected gym's reward photo); preferred over
  /// [imageAsset] when set. Null for the bundled sample items below.
  final String? imageUrl;
  final String imageAsset;
  final String name;
  final String discountLabel;
  final int pointsCost;
}

class ShowcaseRewardsStats {
  const ShowcaseRewardsStats({
    required this.title,
    required this.subtitle,
    required this.featuredIndex,
    required this.items,
  });

  final String title;
  final String subtitle;
  final int featuredIndex;
  final List<ShowcaseRewardItem> items;
}

const showcaseWinsStats = ShowcaseWinsStats(
  title: 'Today’s wins',
  subtitle: 'The grind never stops',
  heroAsset: 'stat_wins_trophy.png',
  tiles: [
    ShowcaseWinTile(iconName: 'star', value: '3 week', label: 'Streak'),
    ShowcaseWinTile(iconName: 'award', value: '28', label: 'Rank Classes'),
    ShowcaseWinTile(iconName: 'gift', value: '+160', label: 'Points'),
  ],
);

const showcasePointsStats = ShowcasePointsStats(
  gained: 160,
  totalPoints: 3400,
);

const showcaseRewardsStats = ShowcaseRewardsStats(
  title: 'Rewards You Can Get',
  subtitle: 'Swipe to view rewards',
  featuredIndex: 1,
  items: [
    ShowcaseRewardItem(
      imageAsset: 'reward_bring_friend.png',
      name: 'Bring a friend',
      discountLabel: 'Free',
      pointsCost: 800,
    ),
    ShowcaseRewardItem(
      imageAsset: 'reward_mma_tshirt.png',
      name: 'Gym t-shirt',
      discountLabel: 'Free',
      pointsCost: 2200,
    ),
    ShowcaseRewardItem(
      imageAsset: 'reward_private_training.png',
      name: 'Private Training',
      discountLabel: '50% off',
      pointsCost: 3500,
    ),
  ],
);
