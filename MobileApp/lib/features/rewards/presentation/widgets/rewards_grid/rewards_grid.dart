import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/rewards/data/mock_my_rewards.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/reward_card/reward_card.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/reward_card/reward_redeem_dialog.dart';

/// Two-column grid of earned rewards. Same shared card as the points
/// store, but the CTA reads "Use" and triggers the redeem dialog.
class RewardsGrid extends StatelessWidget {
  const RewardsGrid({super.key, required this.rewards});

  final List<MockReward> rewards;

  @override
  Widget build(BuildContext context) {
    final left = <MockReward>[];
    final right = <MockReward>[];
    for (var i = 0; i < rewards.length; i++) {
      (i.isEven ? left : right).add(rewards[i]);
    }
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: DesignConstants.screenHorizontalPadding,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: DesignConstants.spacingLarge,
        children: [
          Expanded(child: _RewardsColumn(rewards: left)),
          Expanded(child: _RewardsColumn(rewards: right)),
        ],
      ),
    );
  }
}

class _RewardsColumn extends StatelessWidget {
  const _RewardsColumn({required this.rewards});

  final List<MockReward> rewards;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingLarge,
      children: [
        for (final reward in rewards)
          RewardCard(
            imageAsset: reward.imageAsset,
            title: reward.title,
            priceLabel: reward.priceLabel,
            pointsCost: reward.pointsCost,
            buttonText: 'Use',
            onPressed: () => RewardRedeemDialog.show(
              context,
              imageAsset: reward.imageAsset,
              title: reward.title,
              priceLabel: reward.priceLabel,
              pointsCost: reward.pointsCost,
            ),
          ),
      ],
    );
  }
}
