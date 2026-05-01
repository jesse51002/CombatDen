import 'package:mobile_app/core/branding/brand.dart';

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
  logoAsset: 'gym_logo_global_mma.png',
  streakDays: 3,
  pointsLabel: '3.4k',
  rankBadgeAsset: 'icon_rank_belt.png',
);

const mockGymGlobalBjj = MockGym(
  name: 'Global BJJ',
  logoAsset: 'gym_logo_global_mma.png',
  streakDays: 3,
  pointsLabel: '3.4k',
  rankBadgeAsset: 'icon_rank_belt.png',
);

MockGym mockGymFor(Brand brand) => switch (brand) {
  Brand.combatDen => mockGymGlobalMma,
  Brand.combatDenBjj => mockGymGlobalBjj,
};
