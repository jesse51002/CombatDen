import 'package:flutter/material.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/rewards_tabs/rewards_tabs_segmented.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/rewards_tabs/rewards_tabs_underline.dart';

/// Which tab is currently selected in the rewards tab strip.
enum RewardsTab { pointsStore, myRewards }

/// How the strip is drawn. PRESENTATION ONLY — both values render the
/// same two labelled tap targets with the same one active.
enum RewardsTabsLayout {
  /// Underline on the active tab. Ships today.
  underline,

  /// Both tabs inside one pill; the active one is filled.
  segmented,
}

/// Two-tab selector used on both rewards screens.
class RewardsTabs extends StatelessWidget {
  const RewardsTabs({
    super.key,
    required this.active,
    this.onPointsStoreTap,
    this.onMyRewardsTap,
    this.layout = RewardsTabsLayout.underline,
  });

  final RewardsTab active;
  final VoidCallback? onPointsStoreTap;
  final VoidCallback? onMyRewardsTap;
  final RewardsTabsLayout layout;

  @override
  Widget build(BuildContext context) {
    return switch (layout) {
      RewardsTabsLayout.underline => RewardsTabsUnderline(
        active: active,
        onPointsStoreTap: onPointsStoreTap,
        onMyRewardsTap: onMyRewardsTap,
      ),
      RewardsTabsLayout.segmented => RewardsTabsSegmented(
        active: active,
        onPointsStoreTap: onPointsStoreTap,
        onMyRewardsTap: onMyRewardsTap,
      ),
    };
  }
}
