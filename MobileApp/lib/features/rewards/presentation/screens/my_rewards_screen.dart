import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/core/app_routes.dart';
import 'package:mobile_app/features/rewards/data/mock_my_rewards.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/rewards_grid/rewards_grid.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/rewards_tabs.dart';
import 'package:mobile_app/shared/widgets/nav/app_bottom_nav_bar.dart';
import 'package:mobile_app/shared/widgets/scaffold/app_screen_scaffold.dart';
import 'package:mobile_app/shared/widgets/topbar/app_topbar.dart';

/// Rewards tab landing — "My Rewards". Shows the user's point total and the
/// rewards they've already earned.
class MyRewardsScreen extends StatelessWidget {
  const MyRewardsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final data = mockMyRewardsData;
    return AppScreenScaffold(
      horizontalPadding: AppScreenHorizontalPadding.none,
      bottomNav: const AppBottomNavBar(selected: AppBottomNavTab.reward),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: DesignConstants.spacingBig,
          children: [
            AppTopbar(
              mode: AppTopbarMode.nameOnly,
              showBackButton: false,
              gymName: data.gymName,
              logoAsset: data.gymLogoAsset,
              streakDays: data.streakDays,
              pointsLabel: data.pointsLabel,
              rankBadgeAsset: data.rankBadgeAsset,
            ),
            RewardsTabs(
              active: RewardsTab.myRewards,
              onPointsStoreTap: () => Navigator.of(
                context,
              ).pushReplacementNamed(AppRoutes.pointsStore),
            ),
            RewardsGrid(rewards: data.rewards),
          ],
        ),
      ),
    );
  }
}
