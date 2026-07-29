import 'package:flutter/material.dart';
import 'package:mobile_app/core/app_routes.dart';
import 'package:mobile_app/core/selected_gym.dart';
import 'package:mobile_app/features/gym/data/gym_detail.dart';
import 'package:mobile_app/features/gym/data/gym_repository.dart';
import 'package:mobile_app/features/rewards/data/mock_points_store.dart';
import 'package:mobile_app/features/rewards/data/reward.dart';
import 'package:mobile_app/features/rewards/presentation/layouts/rewards_layout.dart';
import 'package:mobile_app/features/rewards/presentation/layouts/rewards_layout_data.dart';

/// Points store — flat catalog of items the user can redeem with earned
/// points. Each item carries its own points cost.
///
/// This screen owns the LOAD only: it resolves the selected gym's
/// rewards and hands one [RewardsLayoutData] to [RewardsLayout], which
/// arranges it according to the tenant's `rewards_format`.
class PointsStoreScreen extends StatelessWidget {
  const PointsStoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<GymDetail>(
      future: GymRepository.instance.detail(),
      builder: (context, snapshot) =>
          RewardsLayout(data: _data(context, snapshot)),
    );
  }

  RewardsLayoutData _data(
    BuildContext context,
    AsyncSnapshot<GymDetail> snapshot,
  ) {
    final mock = mockPointsStoreData;
    final loading = snapshot.connectionState != ConnectionState.done;
    final rewards = snapshot.data?.rewards ?? const <Reward>[];

    String? message;
    if (!loading) {
      if (snapshot.hasError) {
        message =
            'Could not reach the video service to load the rewards store.';
      } else if (rewards.isEmpty) {
        message = 'No rewards in the store yet.';
      }
    }

    return RewardsLayoutData(
      gymName: selectedGym.displayName,
      logoAsset: mock.gymLogoAsset,
      streakDays: mock.streakDays,
      pointsLabel: mock.pointsLabel,
      rankBadgeAsset: mock.rankBadgeAsset,
      totalPoints: mock.totalPoints,
      rewards: rewards,
      isLoading: loading,
      statusMessage: message,
      onMyRewardsTap: () =>
          Navigator.of(context).pushReplacementNamed(AppRoutes.myRewards),
    );
  }
}
