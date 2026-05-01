/// Hardcoded prototype data for the Profile screen.
///
/// Field names mirror the eventual API contract so the swap to real
/// repositories is mechanical.
library;

import 'package:mobile_app/core/branding/brand.dart';

class MockProfileVideo {
  const MockProfileVideo({
    required this.title,
    required this.viewCount,
    required this.thumbnailAsset,
    required this.creatorAvatarAsset,
  });

  final String title;
  final String viewCount;
  final String thumbnailAsset;
  final String creatorAvatarAsset;
}

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
    required this.ratingGraphAsset,
    required this.nextRankTitle,
    required this.nextRankProgressLabel,
    required this.nextRankProgress,
    required this.nextRankBadgeAsset,
    required this.levelUpVideos,
  });

  final String gymName;
  final int streakDays;
  final String pointsLabel;
  final String rankBadgeAsset;

  final int streakWeeks;

  final String rankTitle;
  final String rankSubtitle;
  final String rankBadgeLargeAsset;
  final String ratingGraphAsset;

  final String nextRankTitle;
  final String nextRankProgressLabel;
  final double nextRankProgress;
  final String nextRankBadgeAsset;

  final List<MockProfileVideo> levelUpVideos;
}

const _kLevelUpVideos = [
  MockProfileVideo(
    title: 'Mauy Thai Basics (Don’t look lik)',
    viewCount: '350K views',
    thumbnailAsset: 'profile_video_thumb.png',
    creatorAvatarAsset: 'profile_creator_pfp.png',
  ),
  MockProfileVideo(
    title: 'We Put Fighters in Self Defense Training',
    viewCount: '350K views',
    thumbnailAsset: 'profile_video_thumb.png',
    creatorAvatarAsset: 'profile_creator_pfp.png',
  ),
];

const mockProfileGlobalMma = MockProfile(
  gymName: 'Global MMA',
  streakDays: 3,
  pointsLabel: '3.4k',
  rankBadgeAsset: 'icon_rank_belt.png',
  streakWeeks: 3,
  rankTitle: 'Gold Belt',
  rankSubtitle: 'Stripe III',
  rankBadgeLargeAsset: 'profile_rank_belt_gold.png',
  ratingGraphAsset: 'profile_rating_graph.png',
  nextRankTitle: 'Next Rank',
  nextRankProgressLabel: 'Silver I (23/50 classes)',
  nextRankProgress: 0.55,
  nextRankBadgeAsset: 'profile_next_rank_belt.png',
  levelUpVideos: _kLevelUpVideos,
);

const mockProfileGlobalBjj = MockProfile(
  gymName: 'Global BJJ',
  streakDays: 3,
  pointsLabel: '3.4k',
  rankBadgeAsset: 'icon_rank_belt.png',
  streakWeeks: 3,
  rankTitle: 'Blue Belt',
  rankSubtitle: 'Stripe II',
  rankBadgeLargeAsset: 'profile_rank_belt_gold.png',
  ratingGraphAsset: 'profile_rating_graph.png',
  nextRankTitle: 'Next Rank',
  nextRankProgressLabel: 'Blue Stripe III (23/50 classes)',
  nextRankProgress: 0.55,
  nextRankBadgeAsset: 'profile_next_rank_belt.png',
  levelUpVideos: _kLevelUpVideos,
);

MockProfile mockProfileFor(Brand brand) => switch (brand) {
  Brand.combatDen => mockProfileGlobalMma,
  Brand.combatDenBjj => mockProfileGlobalBjj,
};

const ratingGraphThresholdsCombatDen = <String>[
  'Bronze III -',
  'Bronze II -',
  'Bronze I -',
];

const ratingGraphThresholdsCombatDenBjj = <String>[
  'White Belt -',
  'Blue Belt -',
];

List<String> ratingGraphThresholdsFor(Brand brand) => switch (brand) {
  Brand.combatDen => ratingGraphThresholdsCombatDen,
  Brand.combatDenBjj => ratingGraphThresholdsCombatDenBjj,
};
