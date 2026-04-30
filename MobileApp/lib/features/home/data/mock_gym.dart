class MockGym {
  const MockGym({
    required this.name,
    required this.logoAsset,
    required this.streakDays,
    required this.pointsLabel,
    required this.rankBadgeAsset,
  });

  final String name;
  final String logoAsset;
  final int streakDays;
  final String pointsLabel;
  final String rankBadgeAsset;
}

const mockGymGlobalMma = MockGym(
  name: 'Global MMA',
  logoAsset: 'assets/images/gym_logo_global_mma.png',
  streakDays: 3,
  pointsLabel: '3.4k',
  rankBadgeAsset: 'assets/images/icon_rank_belt.png',
);
