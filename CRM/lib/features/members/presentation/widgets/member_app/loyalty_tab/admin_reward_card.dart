import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/members/presentation/widgets/member_app/loyalty_tab/reward_image_hero.dart';
import 'package:crm/features/rewards/data/models/reward_response.dart';
import 'package:crm/features/rewards/presentation/dialogs/reward_delete_dialog.dart';
import 'package:crm/features/rewards/presentation/dialogs/reward_form_dialog.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';
import 'package:crm/shared/widgets/app_primary_button.dart';

/// One reward in the admin's points store: the member-facing card art,
/// title, and points cost, with Edit / Remove actions for the admin.
/// Backed by the real [RewardResponse] from the FastApiBackend.
class AdminRewardCard extends StatelessWidget {
  final RewardResponse reward;

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
            imageUrl: reward.imageUrl,
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
                  height: DesignConstants.rewardCardTitleHeight,
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
                  '${formatRewardPoints(reward.pointCost)} pts',
                  style: DesignConstants.h2.copyWith(
                    color: DesignConstants.primaryColor,
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
                        onPressed: () => RewardFormDialog.show(
                          context,
                          existing: reward,
                        ),
                      ),
                    ),
                    Expanded(
                      child: AppPrimaryButton(
                        text: 'Remove',
                        fullWidth: true,
                        backgroundColor: DesignConstants.redDark,
                        onPressed: () => RewardDeleteDialog.show(
                          context,
                          rewardId: reward.rewardId,
                          rewardTitle: reward.title,
                        ),
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
