import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/rewards/presentation/layouts/rewards_layout_data.dart';
import 'package:mobile_app/features/rewards/presentation/layouts/rewards_topbar.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/points_headline.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/rewards_load_status.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/rewards_tabs/rewards_tabs.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/store_grid/store_grid.dart';

/// `RewardsFormat.cardGrid` — the points store that ships today.
///
/// One scroll: topbar, tab strip, points headline, then a two-up grid of
/// image-top cards. Reproduces the previous `PointsStoreScreen` body
/// value for value, so a tenant with no rewards slot sees no change.
class RewardsCardGrid extends StatelessWidget {
  const RewardsCardGrid({super.key, required this.data});

  final RewardsLayoutData data;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingBig,
        children: [
          RewardsTopbar(data: data),
          RewardsTabs(
            active: RewardsTab.pointsStore,
            onMyRewardsTap: data.onMyRewardsTap,
          ),
          PointsHeadline(points: data.totalPoints),
          if (data.hasStatus)
            RewardsLoadStatus(data.statusMessage)
          else
            StoreGrid(items: data.rewards),
        ],
      ),
    );
  }
}
