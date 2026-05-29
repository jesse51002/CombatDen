/// Mock data for the "My Rewards" topbar chrome. The earned reward is now
/// pulled live (one of the selected gym's store rewards — see
/// `GymRepository`); what stays mock is the per-member chrome the gym file
/// can't carry: gym identity, streak, point balance, rank.
library;

class MockMyRewardsData {
  const MockMyRewardsData({
    required this.gymLogoAsset,
    required this.streakDays,
    required this.pointsLabel,
    required this.rankBadgeAsset,
    required this.totalPoints,
  });

  final String gymLogoAsset;
  final int streakDays;
  final String pointsLabel;
  final String rankBadgeAsset;

  final int totalPoints;
}

const mockMyRewardsData = MockMyRewardsData(
  gymLogoAsset: 'gym_logo_global_mma.png',
  streakDays: 3,
  pointsLabel: '3.4k',
  rankBadgeAsset: 'icon_rank_belt.png',
  totalPoints: 3400,
);
