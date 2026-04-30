import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/features/members/data/mock_member_app_preview.dart';
import 'package:app_management/features/members/presentation/widgets/member_app/rewards/reward_row.dart';

/// One redemption tier within the rewards store ("Redeem for 1500
/// points", "Redeem for 3000 points", etc).
///
/// Renders the tier title above a stack of reward rows separated by
/// horizontal dividers.
class RewardsTierSection extends StatelessWidget {
  final int points;
  final List<RewardItem> rewards;

  const RewardsTierSection({
    super.key,
    required this.points,
    required this.rewards,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingBig,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: DesignConstants.paddingSmall,
          ),
          child: Text(
            'Redeem for $points points',
            style: DesignConstants.h2,
          ),
        ),
        ..._buildRowsWithDividers(),
      ],
    );
  }

  List<Widget> _buildRowsWithDividers() {
    final children = <Widget>[];
    for (var i = 0; i < rewards.length; i++) {
      children.add(RewardRow(reward: rewards[i]));
      children.add(_TierDivider());
    }
    return children;
  }
}

class _TierDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: DesignConstants.buttonBorder,
      color: DesignConstants.divider,
    );
  }
}
