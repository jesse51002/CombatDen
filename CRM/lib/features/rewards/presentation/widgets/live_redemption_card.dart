import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/members/presentation/widgets/member_app/loyalty_tab/reward_image_hero.dart';
import 'package:crm/features/rewards/data/models/pending_redemption_item.dart';
import 'package:crm/features/rewards/presentation/dialogs/redemption_action_dialog.dart';
import 'package:crm/shared/widgets/app_primary_button.dart';
import 'package:crm/shared/widgets/info_row.dart';
import 'package:crm/features/rewards/presentation/redemption_format.dart';

/// Real pending-redemption card backed by [PendingRedemptionItem] from the
/// FastApiBackend. Opens [RedemptionActionDialog] (approve + reject) on tap.
///
/// Keeps the same visual chrome as the mock [RedemptionCard] so the Loyalty
/// tab looks identical before and after productionization.
class LiveRedemptionCard extends StatelessWidget {
  final PendingRedemptionItem item;

  const LiveRedemptionCard({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final redeemedStr = formatRedemptionDate(item.requestedAt);
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
          RewardImageHero(imageUrl: item.rewardImageUrl),
          Padding(
            padding: const EdgeInsets.all(DesignConstants.paddingSmall),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: DesignConstants.spacingMedium,
              children: [
                SizedBox(
                  height: DesignConstants.rewardCardTitleHeight,
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Text(
                      item.rewardTitle,
                      style: DesignConstants.h2,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                Text(
                  '${formatRewardPoints(item.pointCost)} pts',
                  style: DesignConstants.h2.copyWith(
                    color: DesignConstants.primaryColor,
                  ),
                  textAlign: TextAlign.center,
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: DesignConstants.spacingSmall,
                  children: [
                    InfoRow(label: 'Member', value: item.memberName),
                    InfoRow(label: 'Requested', value: redeemedStr),
                  ],
                ),
                AppPrimaryButton(
                  text: 'Review & Decide',
                  fullWidth: true,
                  onPressed: () => RedemptionActionDialog.show(
                    context,
                    item: item,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
