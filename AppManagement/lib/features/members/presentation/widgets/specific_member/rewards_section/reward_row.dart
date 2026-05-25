import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/features/members/data/mock_member_history.dart';
import 'package:app_management/features/members/presentation/widgets/member_app/loyalty_tab/reward_image_hero.dart';

// Reserve two lines for the title so cards in the grid align, whether the
// name wraps to one line or two (mirrors the member-app reward card).
const double _kTitleHeight = 42;

/// One redeemed reward, in the same card format as the member-app rewards
/// store: image hero with the cost overlaid, then the reward name and the
/// gym it came from.
class RedeemedRewardCard extends StatelessWidget {
  final RedeemedReward reward;

  const RedeemedRewardCard({super.key, required this.reward});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => debugPrint(
        'TODO: open reward "${reward.rewardName}" detail',
      ),
      borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: DesignConstants.card,
          borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            RewardImageHero(
              imageAsset: reward.imageAsset,
              priceLabel: reward.costLabel,
            ),
            Padding(
              padding: const EdgeInsets.all(DesignConstants.paddingSmall),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: DesignConstants.spacingMedium,
                children: [
                  SizedBox(
                    height: _kTitleHeight,
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: Text(
                        reward.rewardName,
                        style: DesignConstants.h2,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  Text(
                    '${formatRewardPoints(reward.pointsSpent)} pts',
                    style: DesignConstants.h2.copyWith(
                      color: DesignConstants.primaryColor,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
