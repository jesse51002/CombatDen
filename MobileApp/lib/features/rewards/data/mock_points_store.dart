/// Mock data for the Points Store topbar chrome. The reward **items** are now
/// live (the selected gym's rewards from the VideoService — see
/// `GymRepository` / `reward.dart`); what stays mock is the per-member chrome
/// the gym file can't carry: gym identity, streak, point balance, rank.
library;

class MockPointsStoreData {
  const MockPointsStoreData({
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

const mockPointsStoreData = MockPointsStoreData(
  gymLogoAsset: 'gym_logo_global_mma.png',
  streakDays: 3,
  pointsLabel: '3.4k',
  rankBadgeAsset: 'icon_rank_belt.png',
  totalPoints: 3400,
);
