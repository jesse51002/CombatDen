/// Mock data for the "My Rewards" landing of the Rewards tab.
///
/// Field names mirror the eventual API contract so the swap to real
/// repositories is mechanical.
library;

class MockReward {
  const MockReward({
    required this.brand,
    required this.title,
    required this.subtitle,
    required this.imageAsset,
  });

  /// Brand or vendor name shown as the row's headline (e.g. "Venom").
  final String brand;

  /// Item name (e.g. "Hand wraps").
  final String title;

  /// Discount or offer line (e.g. "30% off").
  final String subtitle;

  final String imageAsset;
}

class MockMyRewardsData {
  const MockMyRewardsData({
    required this.gymName,
    required this.gymLogoAsset,
    required this.streakDays,
    required this.pointsLabel,
    required this.rankBadgeAsset,
    required this.totalPoints,
    required this.rewards,
  });

  final String gymName;
  final String gymLogoAsset;
  final int streakDays;
  final String pointsLabel;
  final String rankBadgeAsset;

  final int totalPoints;

  final List<MockReward> rewards;
}

const mockMyRewardsData = MockMyRewardsData(
  gymName: 'Global MMA',
  gymLogoAsset: 'assets/images/gym_logo_global_mma.png',
  streakDays: 3,
  pointsLabel: '3.4k',
  rankBadgeAsset: 'assets/images/icon_rank_belt.png',
  totalPoints: 3400,
  rewards: [
    MockReward(
      brand: 'Venom',
      title: 'Hand wraps',
      subtitle: '30% off',
      imageAsset: 'assets/images/reward_hand_wraps.png',
    ),
    MockReward(
      brand: 'Hayabusa',
      title: 'Boxing gloves',
      subtitle: '20% off',
      imageAsset: 'assets/images/reward_hand_wraps.png',
    ),
    MockReward(
      brand: 'Global MMA',
      title: 'Walk-in pass',
      subtitle: '50% off',
      imageAsset: 'assets/images/reward_hand_wraps.png',
    ),
  ],
);
