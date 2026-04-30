import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/features/members/data/mock_member_history.dart';
import 'package:app_management/features/members/presentation/widgets/specific_member/rewards_section/reward_row.dart';
import 'package:app_management/shared/widgets/subtitle_section.dart';

/// "Recently Redeemed Rewards" section: a heading and a vertical
/// list of [RewardRow]s.
class RewardsSection extends StatelessWidget {
  final List<RedeemedReward> rewards;

  const RewardsSection({super.key, required this.rewards});

  @override
  Widget build(BuildContext context) {
    return SubtitleSection(
      title: 'Recently Redeemed Rewards',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingLarge,
        children: [
          for (final reward in rewards) RewardRow(reward: reward),
        ],
      ),
    );
  }
}
