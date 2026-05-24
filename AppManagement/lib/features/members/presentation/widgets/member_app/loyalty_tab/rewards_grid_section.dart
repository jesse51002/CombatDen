import 'package:flutter/material.dart';

import 'package:app_management/features/members/data/mock_loyalty.dart';
import 'package:app_management/features/members/presentation/widgets/member_app/loyalty_tab/admin_reward_card.dart';
import 'package:app_management/shared/widgets/fill_grid.dart';
import 'package:app_management/shared/widgets/subtitle_section.dart';

/// "Rewards Store" section: the points-based rewards members can redeem,
/// laid out as a reflowing grid of [AdminRewardCard]s.
class RewardsGridSection extends StatelessWidget {
  const RewardsGridSection({super.key});

  @override
  Widget build(BuildContext context) {
    return SubtitleSection(
      title: 'Rewards Store',
      child: FillGrid(
        minItemWidth: 220,
        children: [
          for (final reward in kMockLoyaltyRewards)
            AdminRewardCard(reward: reward),
        ],
      ),
    );
  }
}
