import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/members/presentation/widgets/member_app/loyalty_tab/reward_image_hero.dart';
import 'package:crm/features/rewards/data/models/pending_redemption_item.dart';
import 'package:crm/features/rewards/presentation/dialogs/redemption_action_dialog.dart';
import 'package:crm/shared/widgets/app_primary_button.dart';
import 'package:crm/shared/widgets/info_row.dart';

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
    final redeemedStr = _formatDate(item.redeemedAt);
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

String _formatDate(DateTime dt) {
  final local = dt.toLocal();
  final now = DateTime.now();
  final isToday = local.year == now.year &&
      local.month == now.month &&
      local.day == now.day;
  final hour = local.hour > 12
      ? local.hour - 12
      : (local.hour == 0 ? 12 : local.hour);
  final amPm = local.hour >= 12 ? 'PM' : 'AM';
  final min = local.minute.toString().padLeft(2, '0');
  if (isToday) return 'Today, $hour:$min $amPm';
  final months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${months[local.month - 1]} ${local.day}, $hour:$min $amPm';
}
