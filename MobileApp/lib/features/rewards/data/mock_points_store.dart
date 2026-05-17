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
      priceLabel: 'Free',
      pointsCost: 800,
      imageAsset: 'reward_bring_friend.png',
    ),
    MockPointsStoreItem(
      title: 'Hand wraps',
      priceLabel: '30% off',
      pointsCost: 1500,
      imageAsset: 'reward_hand_wraps.png',
    ),
    MockPointsStoreItem(
      title: 'Private Training\n(15 min)',
      priceLabel: 'Free',
      pointsCost: 1800,
      imageAsset: 'reward_private_training_short.png',
    ),
    MockPointsStoreItem(
      title: 'Gym t-shirt',
      priceLabel: 'Free',
      pointsCost: 2200,
      imageAsset: 'reward_mma_tshirt.png',
    ),
    MockPointsStoreItem(
      title: 'Boxing gloves',
      priceLabel: '10% off',
      pointsCost: 2500,
      imageAsset: 'reward_gloves.png',
    ),
    MockPointsStoreItem(
      title: 'Private Training',
      priceLabel: '50% off',
      pointsCost: 3500,
      imageAsset: 'reward_private_training.png',
    ),
  ],
);
