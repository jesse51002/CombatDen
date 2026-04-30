/// Mock data for the Points Store tab.
library;

class MockPointsStoreItem {
  const MockPointsStoreItem({
    required this.title,
    required this.priceLabel,
    required this.pointsCost,
    required this.imageAsset,
  });

  final String title;

  /// What the user pays on top of the points (often "Free" or a discount).
  final String priceLabel;

  final int pointsCost;

  final String imageAsset;
}

class MockPointsStoreData {
  const MockPointsStoreData({
    required this.gymName,
    required this.gymLogoAsset,
    required this.streakDays,
    required this.pointsLabel,
    required this.rankBadgeAsset,
    required this.totalPoints,
    required this.items,
  });

  final String gymName;
  final String gymLogoAsset;
  final int streakDays;
  final String pointsLabel;
  final String rankBadgeAsset;

  final int totalPoints;
  final List<MockPointsStoreItem> items;
}

const mockPointsStoreData = MockPointsStoreData(
  gymName: 'Global MMA',
  gymLogoAsset: 'gym_logo_global_mma.png',
  streakDays: 3,
  pointsLabel: '3.4k',
  rankBadgeAsset: 'icon_rank_belt.png',
  totalPoints: 3400,
  items: [
    MockPointsStoreItem(
      title: 'Bring a friend',
      priceLabel: 'Free guest pass',
      pointsCost: 800,
      imageAsset: 'reward_bring_friend.png',
    ),
    MockPointsStoreItem(
      title: 'Hayabusa hand wraps',
      priceLabel: r'$25 value',
      pointsCost: 1500,
      imageAsset: 'reward_hand_wraps.png',
    ),
    MockPointsStoreItem(
      title: '15 min private training',
      priceLabel: 'Free session',
      pointsCost: 1800,
      imageAsset: 'reward_private_training_short.png',
    ),
    MockPointsStoreItem(
      title: 'Combat Den gloves',
      priceLabel: r'$60 value',
      pointsCost: 2200,
      imageAsset: 'stat_reward_gloves.png',
    ),
    MockPointsStoreItem(
      title: 'Global MMA t-shirt',
      priceLabel: r'$45 value',
      pointsCost: 2500,
      imageAsset: 'reward_mma_tshirt.png',
    ),
    MockPointsStoreItem(
      title: 'Private training session',
      priceLabel: '50% off',
      pointsCost: 3500,
      imageAsset: 'reward_private_training.png',
    ),
  ],
);
