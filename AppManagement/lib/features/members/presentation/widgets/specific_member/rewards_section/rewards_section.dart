import 'package:flutter/material.dart';

import 'package:app_management/features/members/data/mock_member_history.dart';
import 'package:app_management/features/members/presentation/widgets/specific_member/rewards_section/reward_row.dart';
import 'package:app_management/shared/widgets/fill_grid.dart';
import 'package:app_management/shared/widgets/subtitle_section.dart';

/// "Recently Redeemed Rewards" section: a heading and a reflowing grid of
/// reward cards, matching the member-app rewards store format.
class RewardsSection extends StatelessWidget {
  final List<RedeemedReward> rewards;

  const RewardsSection({super.key, required this.rewards});

  @override
  Widget build(BuildContext context) {
    return SubtitleSection(
      title: 'Recently Redeemed Rewards',
      child: FillGrid(
        minItemWidth: 220,
        children: [
          for (final reward in rewards) RedeemedRewardCard(reward: reward),
        ],
      ),
    );
  }
}
