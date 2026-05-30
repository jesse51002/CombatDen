import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/features/members/presentation/widgets/member_app/loyalty_tab/add_reward_section.dart';
import 'package:app_management/features/members/presentation/widgets/member_app/loyalty_tab/pending_approval_section.dart';
import 'package:app_management/features/members/presentation/widgets/member_app/loyalty_tab/rewards_grid_section.dart';

/// Loyalty tab: the points-based rewards store, an "add your own" grid,
/// and the queue of redemptions awaiting desk confirmation.
class LoyaltyTab extends StatelessWidget {
  const LoyaltyTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingBig,
      children: const [
        PendingApprovalSection(),
        RewardsGridSection(),
        AddRewardSection(),
      ],
    );
  }
}
