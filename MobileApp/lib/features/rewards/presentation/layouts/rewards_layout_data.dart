import 'package:flutter/foundation.dart';
import 'package:mobile_app/features/rewards/data/reward.dart';

/// Everything a points-store layout renders.
///
/// Identical for every `RewardsFormat`: the topbar chrome, the member's
/// point total, the store's rewards, and the load state. A format
/// rearranges this payload — it never reaches past it for data the
/// shipped screen did not already have.
@immutable
class RewardsLayoutData {
  const RewardsLayoutData({
    required this.gymName,
    required this.logoAsset,
    required this.streakDays,
    required this.pointsLabel,
    required this.rankBadgeAsset,
    required this.totalPoints,
    this.rewards = const <Reward>[],
    this.isLoading = false,
    this.statusMessage,
    this.onMyRewardsTap,
  });

  // Topbar chrome.
  final String gymName;
  final String logoAsset;
  final int streakDays;
  final String pointsLabel;
  final String rankBadgeAsset;

  /// The member's point balance — the headline, and the yardstick the
  /// price ladder bands against. Already on the screen today.
  final int totalPoints;

  final List<Reward> rewards;

  /// The store is still loading; the load status shows its spinner.
  final bool isLoading;

  /// The error / empty copy, or null when there is nothing to say.
  final String? statusMessage;

  final VoidCallback? onMyRewardsTap;

  /// True when the load status stands in for the store — exactly the
  /// three cases the shipped screen has: loading, error, empty.
  bool get hasStatus => isLoading || statusMessage != null;
}
