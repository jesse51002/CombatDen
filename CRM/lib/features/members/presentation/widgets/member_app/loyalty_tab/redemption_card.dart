import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/members/data/mock_loyalty.dart';
import 'package:crm/features/members/presentation/widgets/member_app/loyalty_tab/reward_confirm_dialog.dart';
import 'package:crm/features/members/presentation/widgets/member_app/loyalty_tab/reward_image_hero.dart';
import 'package:crm/shared/widgets/app_primary_button.dart';
import 'package:crm/shared/widgets/info_row.dart';

/// One member redemption awaiting desk confirmation: the reward art the
/// member sees, who requested it and when, and a button to open the
/// confirm dialog. Visual so staff recognize the reward at a glance.
class RedemptionCard extends StatelessWidget {
  final PendingRedemption redemption;

  const RedemptionCard({super.key, required this.redemption});

  @override
  Widget build(BuildContext context) {
    final r = redemption;
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
            imageAsset: r.imageAsset,
            imageUrl: r.imageUrl,
            priceLabel: r.priceLabel,
          ),
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
                      r.rewardTitle,
                      style: DesignConstants.h2,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                Text(
                  '${formatRewardPoints(r.pointsCost)} pts',
                  style: DesignConstants.h2.copyWith(
                    color: DesignConstants.primaryColor,
                  ),
                  textAlign: TextAlign.center,
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: DesignConstants.spacingSmall,
                  children: [
                    InfoRow(label: 'Member', value: r.memberName),
                    InfoRow(label: 'Code', value: r.code),
                    InfoRow(label: 'Requested', value: r.requestedAt),
                  ],
                ),
                if (r.approved)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    spacing: DesignConstants.spacingSmall,
                    children: [
                      Icon(
                        Symbols.check_circle_sharp,
                        color: DesignConstants.goodGreen,
                        weight: DesignConstants.iconWeight,
                        size: DesignConstants.iconSizeMedium,
                      ),
                      Text(
                        'Approved',
                        style: DesignConstants.h2.copyWith(
                          color: DesignConstants.goodGreen,
                        ),
                      ),
                    ],
                  )
                else
                  AppPrimaryButton(
                    text: 'Review & confirm',
                    fullWidth: true,
                    onPressed: () => RewardConfirmDialog.show(context, r),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
