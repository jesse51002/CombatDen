import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/features/members/data/mock_member_history.dart';

/// Single redeemed-reward row inside the "Recently Redeemed Rewards"
/// section: text block on the left, circular product thumbnail on
/// the right.
class RewardRow extends StatelessWidget {
  final RedeemedReward reward;

  const RewardRow({super.key, required this.reward});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => debugPrint(
        'TODO: open reward "${reward.rewardName}" detail',
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        spacing: DesignConstants.spacingLarge,
        children: [
          Expanded(child: _TextBlock(reward: reward)),
          _Thumbnail(asset: reward.imageAsset),
        ],
      ),
    );
  }
}

class _TextBlock extends StatelessWidget {
  final RedeemedReward reward;
  const _TextBlock({required this.reward});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingSmall,
      children: [
        Text(reward.gymName, style: DesignConstants.h3),
        Text(reward.rewardName, style: DesignConstants.p),
        Text(
          reward.costLabel,
          style: DesignConstants.p.copyWith(
            color: DesignConstants.text2nd,
          ),
        ),
      ],
    );
  }
}

class _Thumbnail extends StatelessWidget {
  final String asset;
  const _Thumbnail({required this.asset});

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: Image.asset(
        asset,
        width: 100,
        height: 100,
        fit: BoxFit.cover,
      ),
    );
  }
}
