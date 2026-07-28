import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/rewards/presentation/layouts/rewards_layout_data.dart';
import 'package:mobile_app/features/rewards/presentation/layouts/rewards_topbar.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/points_headline.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/reward_card/reward_card_data.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/reward_card/reward_store_card.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/rewards_load_status.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/rewards_tabs/rewards_tabs.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/store_grid/store_grid.dart';

/// `RewardsFormat.storefrontHero` — the retail storefront.
///
/// The first reward is promoted to a full-bleed hero with its title,
/// cost and action riding the image; the points headline drops below it,
/// and the remaining rewards fall into the same two-up grid. The
/// promoted reward is not a copy — it is taken OUT of the grid, so every
/// reward still appears exactly once.
class RewardsStorefrontHero extends StatelessWidget {
  const RewardsStorefrontHero({super.key, required this.data});

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
            layout: RewardsTabsLayout.segmented,
            onMyRewardsTap: data.onMyRewardsTap,
          ),
          if (data.hasStatus) ...[
            PointsHeadline(points: data.totalPoints),
            RewardsLoadStatus(data.statusMessage),
          ] else ...[
            RewardStoreCard(
              reward: data.rewards.first,
              layout: RewardCardLayout.hero,
            ),
            PointsHeadline(points: data.totalPoints),
            StoreGrid(items: data.rewards.skip(1).toList()),
          ],
        ],
      ),
    );
  }
}
