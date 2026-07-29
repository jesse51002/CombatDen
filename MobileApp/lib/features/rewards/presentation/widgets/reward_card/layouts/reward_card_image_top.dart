import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/reward_card/parts/reward_card_shell.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/reward_card/parts/reward_image_hero.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/reward_card/parts/reward_points_cost.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/reward_card/parts/reward_title.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/reward_card/reward_card_data.dart';
import 'package:mobile_app/shared/widgets/buttons/app_primary_button.dart';

/// `RewardCardLayout.imageTop` — the card that ships today.
///
/// 3:2 image with the price tag pinned top-right; beneath it a
/// fixed-height title slot, the points cost, and a full-width action.
/// Reproduces the previous `RewardCard` value for value.
class RewardCardImageTop extends StatelessWidget {
  const RewardCardImageTop({super.key, required this.data});

  final RewardCardData data;

  @override
  Widget build(BuildContext context) {
    return RewardCardShell(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RewardImageHero(
            imageUrl: data.imageUrl,
            priceLabel: data.priceLabel,
          ),
          Padding(
            padding: EdgeInsets.all(DesignConstants.paddingSmall),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: DesignConstants.spacingMedium,
              children: [
                RewardTitle(
                  title: data.title,
                  maxLines: 2,
                  reserveHeight: kRewardTitleTwoLine,
                ),
                RewardPointsCost(pointsCost: data.pointsCost),
                AppPrimaryButton(
                  text: data.buttonText,
                  fullWidth: true,
                  onPressed: data.onPressed,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
