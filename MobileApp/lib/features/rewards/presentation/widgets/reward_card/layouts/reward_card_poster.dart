import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/reward_card/parts/reward_card_shell.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/reward_card/parts/reward_image_hero.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/reward_card/parts/reward_points_cost.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/reward_card/parts/reward_title.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/reward_card/reward_card_data.dart';
import 'package:mobile_app/shared/widgets/buttons/app_primary_button.dart';

/// `RewardCardLayout.poster` — one reward, given the whole deck.
///
/// The image takes every pixel the deck's height leaves after the title,
/// the cost, and the action, so the poster adapts to the phone instead
/// of pinning a ratio that overflows on a short screen.
///
/// The action stays INSIDE the poster. Lifting it out to a single
/// pinned button under the deck would leave the card without the one
/// element the reward-card contract says it carries, and would make the
/// button ambiguous mid-swipe — see `RewardsPosterDeck`.
class RewardCardPoster extends StatelessWidget {
  const RewardCardPoster({super.key, required this.data});

  final RewardCardData data;

  @override
  Widget build(BuildContext context) {
    return RewardCardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: RewardImageHero(
              imageUrl: data.imageUrl,
              priceLabel: data.priceLabel,
              aspectRatio: null,
            ),
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
                RewardPointsCost(
                  pointsCost: data.pointsCost,
                  style: DesignConstants.h1.copyWith(
                    color: DesignConstants.primaryColor,
                  ),
                ),
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
