import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/features/members/data/mock_loyalty.dart';
import 'package:app_management/features/members/presentation/widgets/member_app/loyalty_tab/reward_image_hero.dart';
import 'package:app_management/shared/widgets/app_outline_button.dart';
import 'package:app_management/shared/widgets/app_primary_button.dart';

// Reserve two lines of h2 so every card's title block is the same height
// whether the title wraps to one line or two (mirrors the member app).
const double _kCardTitleHeight = 42;

/// One reward in the admin's points store: the member-facing card art,
/// title, and points cost, with Edit / Remove actions for the admin.
class AdminRewardCard extends StatelessWidget {
  final LoyaltyReward reward;

  const AdminRewardCard({super.key, required this.reward});

  @override
  Widget build(BuildContext context) {
    return Container(
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
            priceLabel: reward.priceLabel,
          ),
          Padding(
            padding: const EdgeInsets.all(DesignConstants.paddingSmall),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: DesignConstants.spacingMedium,
              children: [
                SizedBox(
                  height: _kCardTitleHeight,
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Text(
                      reward.title,
                      style: DesignConstants.h2,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                Text(
                  '${formatRewardPoints(reward.pointsCost)} pts',
                  style: DesignConstants.h2.copyWith(
                    color: DesignConstants.lightPrimary,
                  ),
                  textAlign: TextAlign.center,
                ),
                Row(
                  spacing: DesignConstants.spacingMedium,
                  children: [
                    Expanded(
                      child: AppOutlineButton(
                        text: 'Edit',
                        fullWidth: true,
                        onPressed: () => debugPrint('TODO: edit reward'),
                      ),
                    ),
                    Expanded(
                      child: AppPrimaryButton(
                        text: 'Remove',
                        fullWidth: true,
                        backgroundColor: DesignConstants.redDark,
                        onPressed: () => debugPrint('TODO: remove reward'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
