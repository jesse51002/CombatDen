import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/reward_card/parts/reward_image_hero.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/reward_card/parts/reward_points_cost.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/reward_card/parts/reward_price_tag.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/reward_card/parts/reward_title.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/reward_card/reward_card_data.dart';
import 'package:mobile_app/shared/widgets/buttons/app_primary_button.dart';

// The square thumb's edge. An asset-bound dimension, not a spacing token.
const double _kThumbSize = 76;

/// `RewardCardLayout.thumbLeft` — a full-width row.
///
/// Square thumb leading, title over an inline price tag + cost, action
/// trailing, hairline rule beneath. Scans faster than a grid when titles
/// are long, which is the case the 2-line clamp papers over.
class RewardCardThumbLeft extends StatelessWidget {
  const RewardCardThumbLeft({super.key, required this.data});

  final RewardCardData data;

  @override
  Widget build(BuildContext context) {
    return Container(
      // The row's own height; the hairline is its bottom edge.
      padding: EdgeInsets.symmetric(vertical: DesignConstants.spacingLarge),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: DesignConstants.divider,
            width: DesignConstants.dividerThickness,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        spacing: DesignConstants.spacingLarge,
        children: [
          SizedBox(
            width: _kThumbSize,
            child: RewardImageHero(
              imageUrl: data.imageUrl,
              priceLabel: data.priceLabel,
              aspectRatio: 1,
              showPriceTag: false,
              borderRadius: BorderRadius.circular(
                DesignConstants.radiusSmall,
              ),
            ),
          ),
          Expanded(child: _RowMeta(data: data)),
          AppPrimaryButton(
            text: data.buttonText,
            onPressed: data.onPressed,
          ),
        ],
      ),
    );
  }
}

/// Title over the inline price tag and points cost.
class _RowMeta extends StatelessWidget {
  const _RowMeta({required this.data});

  final RewardCardData data;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingSmall,
      children: [
        RewardTitle(
          title: data.title,
          maxLines: 1,
          textAlign: TextAlign.left,
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          spacing: DesignConstants.spacingMedium,
          children: [
            Flexible(child: RewardPriceTag(label: data.priceLabel)),
            Flexible(
              child: RewardPointsCost(
                pointsCost: data.pointsCost,
                style: DesignConstants.h3.copyWith(
                  color: DesignConstants.primaryColor,
                ),
                textAlign: TextAlign.left,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
