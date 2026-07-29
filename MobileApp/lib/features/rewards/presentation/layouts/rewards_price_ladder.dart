import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/rewards/presentation/layouts/rewards_band_section.dart';
import 'package:mobile_app/features/rewards/presentation/layouts/rewards_bands.dart';
import 'package:mobile_app/features/rewards/presentation/layouts/rewards_layout_data.dart';
import 'package:mobile_app/features/rewards/presentation/layouts/rewards_topbar.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/points_headline.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/rewards_load_status.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/rewards_tabs/rewards_tabs.dart';

/// `RewardsFormat.priceLadder` — the store as a savings ladder.
///
/// The points headline pins above the content so the member's balance
/// stays on screen while they scroll, and the rewards group into cost
/// bands, cheapest first, each labelled by how far off it is. Bands come
/// from `pointsCost` and the balance — both already on the shipped
/// screen — so nothing new is fetched.
class RewardsPriceLadder extends StatelessWidget {
  const RewardsPriceLadder({super.key, required this.data});

  final RewardsLayoutData data;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingLarge,
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
          Expanded(child: _Bands(data: data)),
      ],
    );
  }
}

class _Bands extends StatelessWidget {
  const _Bands({required this.data});

  final RewardsLayoutData data;

  @override
  Widget build(BuildContext context) {
    final bands = rewardBands(data.rewards, data.totalPoints);
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(
        horizontal: DesignConstants.screenHorizontalPadding,
        vertical: DesignConstants.spacingMedium,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingBig,
        children: [
          for (final band in bands) RewardBandSection(band: band),
        ],
      ),
    );
  }
}
