import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/rewards/data/reward.dart';
import 'package:mobile_app/features/rewards/presentation/layouts/rewards_layout_data.dart';
import 'package:mobile_app/features/rewards/presentation/layouts/rewards_topbar.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/points_headline.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/reward_card/reward_card_data.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/reward_card/reward_store_card.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/rewards_load_status.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/rewards_tabs/rewards_tabs.dart';

/// `RewardsFormat.listRows` — the same stack, one reward per full-width
/// row instead of two per grid row.
///
/// Square thumb leads, the price tag moves inline beside the cost, the
/// action goes trailing. Titles get the full width, so the two-line
/// clamp stops deciding what a reward is called.
class RewardsListRows extends StatelessWidget {
  const RewardsListRows({super.key, required this.data});

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
            _RowList(items: data.rewards),
        ],
      ),
    );
  }
}

class _RowList extends StatelessWidget {
  const _RowList({required this.items});

  final List<Reward> items;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: DesignConstants.screenHorizontalPadding,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // No `spacing:` on purpose — each row owns its vertical
          // padding and closes with a hairline, which IS the rhythm.
          for (final item in items)
            RewardStoreCard(
              reward: item,
              layout: RewardCardLayout.thumbLeft,
            ),
        ],
      ),
    );
  }
}
