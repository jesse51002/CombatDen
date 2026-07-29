import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/rewards/data/reward.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/reward_card/reward_store_card.dart';

/// Two-column grid of earned rewards. Same shared card as the points
/// store, but the CTA reads "Use" and triggers the redeem dialog.
class RewardsGrid extends StatelessWidget {
  const RewardsGrid({super.key, required this.rewards});

  final List<Reward> rewards;

  @override
  Widget build(BuildContext context) {
    final left = <Reward>[];
    final right = <Reward>[];
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

  final List<Reward> rewards;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingLarge,
      children: [
        for (final reward in rewards)
          RewardStoreCard(reward: reward, buttonText: 'Use'),
      ],
    );
  }
}
