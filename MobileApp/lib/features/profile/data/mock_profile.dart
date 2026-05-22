/// Hardcoded prototype data for the Profile screen.
///
/// Field names mirror the eventual API contract so the swap to real
/// repositories is mechanical.
library;

class MockProfile {
  const MockProfile({
    required this.gymName,
    required this.streakDays,
    required this.pointsLabel,
    required this.rankBadgeAsset,
    required this.streakWeeks,
    required this.rankTitle,
    required this.rankSubtitle,
    required this.rankBadgeLargeAsset,
    required this.nextRankTitle,
    required this.nextRankProgressLabel,
    required this.nextRankProgress,
    required this.nextRankBadgeAsset,
  });

  final String gymName;
  final int streakDays;
  final String pointsLabel;
  final String rankBadgeAsset;

  final int streakWeeks;

  final String rankTitle;
  final String rankSubtitle;
  final String rankBadgeLargeAsset;

  final String nextRankTitle;
  final String nextRankProgressLabel;
  final double nextRankProgress;
  final String nextRankBadgeAsset;
}

const mockProfileGlobalMma = MockProfile(
  gymName: 'Global MMA',
  streakDays: 3,
  pointsLabel: '3.4k',
  rankBadgeAsset: 'icon_rank_belt.png',
  streakWeeks: 3,
  rankTitle: 'Blue Belt',
  rankSubtitle: 'Stripe II',
  rankBadgeLargeAsset: 'profile_rank_belt_gold.png',
  nextRankTitle: 'Next Rank',
  nextRankProgressLabel: 'Blue Stripe III (23/50 classes)',
  nextRankProgress: 0.55,
  nextRankBadgeAsset: 'profile_next_rank_belt.png',
);

/// Single canonical dataset. Per-tenant variation now comes from
/// the customization engine, not a compile-time Brand enum.
MockProfile get mockProfile => mockProfileGlobalMma;

const ratingGraphThresholdsCombatDen = <String>[
  'White Belt -',
  'Blue Belt -',
];

List<String> get ratingGraphThresholds =>
    ratingGraphThresholdsCombatDen;

/// Mock rating-over-time series for the rank summary graph.
///
/// Values are y-coordinates normalized to 0..1, where 0 is the bottom of the
/// chart and 1 is the top. X is implied — points are spaced uniformly across
/// the chart width. The shape is a slow start that accelerates toward the
/// top-right, mirroring the original design placeholder.
const List<double> mockRatingGraphSeries = <double>[
  0.06,
  0.08,
  0.11,
  0.13,
  0.14,
  0.17,
  0.21,
  0.26,
  0.31,
  0.37,
  0.44,
  0.55,
  0.69,
  0.86,
  0.96,
];
