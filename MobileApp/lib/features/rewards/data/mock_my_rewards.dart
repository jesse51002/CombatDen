/// Mock data for the "My Rewards" landing of the Rewards tab.
///
/// Field names mirror the eventual API contract so the swap to real
/// repositories is mechanical.
library;

class MockReward {
  const MockReward({
    required this.title,
    required this.priceLabel,
    required this.pointsCost,
    required this.imageAsset,
  });

  /// Item name (e.g. "Hand wraps").
  final String title;

  /// Discount or "Free" label shown as a tag in the top-right of the card.
  final String priceLabel;

  /// Points the member spent to redeem this reward.
  final int pointsCost;

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
  gymLogoAsset: 'gym_logo_global_mma.png',
  streakDays: 3,
  pointsLabel: '3.4k',
  rankBadgeAsset: 'icon_rank_belt.png',
  totalPoints: 3400,
  rewards: [
    MockReward(
      title: 'Hand wraps',
      priceLabel: '30% off',
      pointsCost: 1500,
      imageAsset: 'reward_hand_wraps.png',
    ),
    MockReward(
      title: 'Boxing gloves',
      priceLabel: '10% off',
      pointsCost: 2500,
      imageAsset: 'stat_reward_gloves.png',
    ),
    MockReward(
      title: 'Bring a friend',
      priceLabel: 'Free',
      pointsCost: 800,
      imageAsset: 'reward_bring_friend.png',
    ),
  ],
);
