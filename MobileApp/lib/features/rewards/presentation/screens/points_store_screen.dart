import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/core/app_routes.dart';
import 'package:mobile_app/core/selected_gym.dart';
import 'package:mobile_app/features/gym/data/gym_detail.dart';
import 'package:mobile_app/features/gym/data/gym_repository.dart';
import 'package:mobile_app/features/rewards/data/mock_points_store.dart';
import 'package:mobile_app/features/rewards/data/reward.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/points_headline.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/rewards_load_status.dart';
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
              gymName: selectedGym.displayName,
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
            const _StoreGridSection(),
          ],
        ),
      ),
    );
  }
}

/// The live store grid: the selected gym's rewards from the VideoService.
class _StoreGridSection extends StatelessWidget {
  const _StoreGridSection();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<GymDetail>(
      future: GymRepository.instance.detail(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const RewardsLoadStatus(null);
        }
        if (snapshot.hasError) {
          return const RewardsLoadStatus(
            'Could not reach the video service to load the rewards store.',
          );
        }
        final rewards = snapshot.data?.rewards ?? const <Reward>[];
        if (rewards.isEmpty) {
          return const RewardsLoadStatus('No rewards in the store yet.');
        }
        return StoreGrid(items: rewards);
      },
    );
  }
}
