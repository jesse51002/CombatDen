import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/reward_card_model.dart';

/// A card displaying a recently redeemed reward.
/// Not tappable.
class RewardCard extends StatelessWidget {
  final RewardCardModel reward;

  const RewardCard({
    super.key,
    required this.reward,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 120.0,
      child: Column(
        children: [
          // Image
          ClipRRect(
            borderRadius: BorderRadius.circular(
              DesignConstants.radiusSmall,
            ),
            child: SizedBox(
              width: 120.0,
              height: 80.0,
              child: reward.imageUrl != null
                  ? Image.network(
                      reward.imageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          _placeholder(),
                    )
                  : _placeholder(),
            ),
          ),
          const SizedBox(
            height:
                DesignConstants.spacingSmall,
          ),
          // Title
          Text(
            reward.title,
            style: DesignConstants.p,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          // Amount off
          if (reward.amountOff != null)
            Text(
              reward.amountOff!,
              style: DesignConstants.pSmall.copyWith(
                color: DesignConstants.text2nd,
              ),
              textAlign: TextAlign.center,
            ),
        ],
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      color: DesignConstants.cardBackground,
      child: const Center(
        child: Icon(
          Icons.image,
          color: DesignConstants.text,
          size: 32,
        ),
      ),
    );
  }
}
