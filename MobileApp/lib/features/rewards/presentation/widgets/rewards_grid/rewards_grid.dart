import 'package:flutter/material.dart';
import 'package:mobile_app/core/constants/design_constants.dart';
import 'package:mobile_app/features/rewards/data/mock_my_rewards.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/rewards_grid/my_reward_card.dart';

/// Two-column grid of earned rewards.
class RewardsGrid extends StatelessWidget {
  const RewardsGrid({super.key, required this.rewards});

  final List<MockReward> rewards;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: DesignConstants.screenHorizontalPadding,
      ),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: rewards.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: DesignConstants.spacingLarge,
          mainAxisSpacing: DesignConstants.spacingLarge,
          childAspectRatio: 0.72,
        ),
        itemBuilder: (context, i) => MyRewardCard(reward: rewards[i]),
      ),
    );
  }
}
