class MockGym {
  const MockGym({
    required this.logoAsset,
    required this.streakDays,
    required this.pointsLabel,
    required this.rankBadgeAsset,
  });

  final String logoAsset;
  final int streakDays;
  final String pointsLabel;
  final String rankBadgeAsset;
}

const mockGymGlobalMma = MockGym(
  logoAsset: 'gym_logo_global_mma.png',
  streakDays: 3,
  pointsLabel: '3.4k',
  rankBadgeAsset: 'icon_rank_belt.png',
);

/// Single canonical dataset. Per-tenant variation now comes from
/// the customization engine, not a compile-time Brand enum.
MockGym get mockGym => mockGymGlobalMma;
