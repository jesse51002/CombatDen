import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/features/members/data/mock_loyalty.dart';
import 'package:app_management/features/members/presentation/widgets/member_app/loyalty_tab/reward_confirm_dialog.dart';
import 'package:app_management/features/members/presentation/widgets/member_app/loyalty_tab/reward_image_hero.dart';
import 'package:app_management/shared/widgets/app_primary_button.dart';
import 'package:app_management/shared/widgets/info_row.dart';

// Two lines of h2 so every card's title block is the same height.
const double _kCardTitleHeight = 42;

/// One member redemption awaiting desk confirmation: the reward art the
/// member sees, who requested it and when, and a button to open the
/// confirm dialog. Visual so staff recognize the reward at a glance.
class PendingApprovalCard extends StatelessWidget {
  final PendingRedemption redemption;

  const PendingApprovalCard({super.key, required this.redemption});

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
          RewardImageHero(imageAsset: r.imageAsset, priceLabel: r.priceLabel),
          Padding(
            padding: const EdgeInsets.all(DesignConstants.paddingSmall),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: DesignConstants.spacingMedium,
              children: [
                SizedBox(
                  height: _kCardTitleHeight,
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
                    color: DesignConstants.lightPrimary,
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
