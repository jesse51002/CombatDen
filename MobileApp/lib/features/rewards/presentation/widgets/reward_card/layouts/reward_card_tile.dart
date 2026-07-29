import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/reward_card/parts/reward_card_shell.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/reward_card/parts/reward_image_hero.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/reward_card/parts/reward_points_cost.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/reward_card/parts/reward_title.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/reward_card/reward_card_data.dart';
import 'package:mobile_app/shared/widgets/buttons/app_primary_button.dart';

/// `RewardCardLayout.tile` — the dense square used inside a cost band,
/// three to a row. Square image with the tag in its corner, one line of
/// title, a small cost, and a small full-width action.
class RewardCardTile extends StatelessWidget {
  const RewardCardTile({super.key, required this.data});

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
            aspectRatio: 1,
          ),
          Padding(
            padding: EdgeInsets.all(DesignConstants.spacingMedium),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: DesignConstants.spacingSmall,
              children: [
                RewardTitle(
                  title: data.title,
                  maxLines: 1,
                  style: DesignConstants.p,
                ),
                RewardPointsCost(
                  pointsCost: data.pointsCost,
                  style: DesignConstants.pSmall.copyWith(
                    color: DesignConstants.primaryColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                AppPrimaryButton(
                  text: data.buttonText,
                  fullWidth: true,
                  textStyle: DesignConstants.pSmall,
                  padding: EdgeInsets.symmetric(
                    horizontal: DesignConstants.spacingSmall,
                    vertical: DesignConstants.spacingSmall,
                  ),
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
