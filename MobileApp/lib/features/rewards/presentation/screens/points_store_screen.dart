import 'package:flutter/material.dart';
import 'package:mobile_app/core/constants/design_constants.dart';
import 'package:mobile_app/core/navigation/app_routes.dart';
import 'package:mobile_app/features/rewards/data/mock_points_store.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/points_headline.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/rewards_tabs.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/store_grid/store_grid.dart';
import 'package:mobile_app/shared/widgets/nav/app_bottom_nav_bar.dart';
import 'package:mobile_app/shared/widgets/scaffold/app_screen_scaffold.dart';
import 'package:mobile_app/shared/widgets/topbar/app_topbar.dart';

/// Points store — flat catalog of items the user can redeem with earned
/// points. Each item carries its own points cost.
class PointsStoreScreen extends StatelessWidget {
  const PointsStoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final data = mockPointsStoreData;
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
              active: RewardsTab.pointsStore,
              onMyRewardsTap: () => Navigator.of(
                context,
              ).pushReplacementNamed(AppRoutes.myRewards),
            ),
            PointsHeadline(points: data.totalPoints),
            StoreGrid(items: data.items),
          ],
        ),
      ),
    );
  }
}
