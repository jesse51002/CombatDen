import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/core/app_routes.dart';
import 'package:mobile_app/core/selected_gym.dart';
import 'package:mobile_app/features/gym/data/gym_detail.dart';
import 'package:mobile_app/features/gym/data/gym_repository.dart';
import 'package:mobile_app/features/rewards/data/mock_my_rewards.dart';
import 'package:mobile_app/features/rewards/data/reward.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/rewards_grid/rewards_grid.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/rewards_load_status.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/rewards_tabs/rewards_tabs.dart';
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
              gymName: selectedGym.displayName,
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
            const _MyRewardsSection(),
          ],
        ),
      ),
    );
  }
}

/// The member's earned rewards. For the prototype this surfaces one of the
/// gym's live store rewards as a redeemed item (real per-member redemptions
/// need a user backend that doesn't exist yet).
class _MyRewardsSection extends StatelessWidget {
  const _MyRewardsSection();

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
            'Could not reach the video service to load your rewards.',
          );
        }
        final rewards = snapshot.data?.rewards ?? const <Reward>[];
        if (rewards.isEmpty) {
          return const RewardsLoadStatus('No rewards earned yet.');
        }
        // Simple: one of the store's rewards stands in as "earned".
        return RewardsGrid(rewards: rewards.take(1).toList());
      },
    );
  }
}
