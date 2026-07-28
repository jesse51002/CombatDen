import 'package:flutter/material.dart';
import 'package:mobile_app/features/rewards/data/reward.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/reward_card/reward_card.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/reward_card/reward_card_data.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/reward_card/reward_redeem_dialog.dart';

/// One live [Reward] as a card, wired to the redeem dialog.
///
/// The single place a reward's action is defined, so every screen format
/// and both rewards grids get the same behaviour and no arrangement can
/// quietly wire a different one.
class RewardStoreCard extends StatelessWidget {
  const RewardStoreCard({
    super.key,
    required this.reward,
    this.layout = RewardCardLayout.imageTop,
    this.buttonText = 'Redeem',
  });

  final Reward reward;
  final RewardCardLayout layout;
  final String buttonText;

  @override
  Widget build(BuildContext context) {
    return RewardCard(
      layout: layout,
      imageUrl: reward.imageUrl,
      title: reward.title,
      priceLabel: reward.priceLabel,
      pointsCost: reward.pointsCost,
      buttonText: buttonText,
      onPressed: () => RewardRedeemDialog.show(
        context,
        imageUrl: reward.imageUrl,
        title: reward.title,
        priceLabel: reward.priceLabel,
        pointsCost: reward.pointsCost,
      ),
    );
  }
}
