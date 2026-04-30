import 'package:flutter/material.dart';
import 'package:mobile_app/core/constants/design_constants.dart';
import 'package:mobile_app/features/rewards/data/mock_my_rewards.dart';
import 'package:mobile_app/shared/widgets/buttons/app_primary_button.dart';

/// Single earned reward rendered as a card in the My Rewards grid.
class MyRewardCard extends StatelessWidget {
  const MyRewardCard({super.key, required this.reward});

  final MockReward reward;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: DesignConstants.card,
        borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Image.asset(reward.imageAsset, fit: BoxFit.cover),
          ),
          Padding(
            padding: EdgeInsets.all(DesignConstants.paddingSmall),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: DesignConstants.spacingMedium,
              children: [
                _TitleAndBrand(reward: reward),
                _Discount(subtitle: reward.subtitle),
                AppPrimaryButton(
                  text: 'Use',
                  fullWidth: true,
                  onPressed: () {},
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TitleAndBrand extends StatelessWidget {
  const _TitleAndBrand({required this.reward});

  final MockReward reward;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: DesignConstants.spacingTiny,
      children: [
        Text(
          reward.title,
          style: DesignConstants.h2,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          reward.brand,
          style: DesignConstants.p.copyWith(color: DesignConstants.text2nd),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _Discount extends StatelessWidget {
  const _Discount({required this.subtitle});

  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Text(
      subtitle,
      style: DesignConstants.h2.copyWith(color: DesignConstants.primaryColor),
      textAlign: TextAlign.center,
    );
  }
}
