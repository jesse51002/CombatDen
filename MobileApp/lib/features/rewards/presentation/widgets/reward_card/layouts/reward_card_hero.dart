import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/reward_card/parts/reward_image_hero.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/reward_card/parts/reward_points_cost.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/reward_card/parts/reward_title.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/reward_card/reward_card_data.dart';
import 'package:mobile_app/shared/widgets/buttons/app_primary_button.dart';

// 16:9. A per-image ratio, not a spacing token.
const double _kHeroRatio = 16 / 9;

/// `RewardCardLayout.hero` — the promoted reward, full bleed.
///
/// The image runs edge to edge with the price tag in its corner; title,
/// cost and action ride the bottom of the image over a scrim. Same five
/// elements as every other card layout, stacked instead of listed.
class RewardCardHero extends StatelessWidget {
  const RewardCardHero({super.key, required this.data});

  final RewardCardData data;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: _kHeroRatio,
      child: Stack(
        fit: StackFit.expand,
        children: [
          RewardImageHero(
            imageUrl: data.imageUrl,
            priceLabel: data.priceLabel,
            aspectRatio: null,
          ),
          const Positioned.fill(child: _HeroScrim()),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Padding(
              padding: EdgeInsets.all(DesignConstants.paddingSmall),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: DesignConstants.spacingMedium,
                children: [
                  RewardTitle(
                    title: data.title,
                    maxLines: 1,
                    style: DesignConstants.h1,
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
          ),
        ],
      ),
    );
  }
}

/// Keeps the overlaid text legible over any photograph.
class _HeroScrim extends StatelessWidget {
  const _HeroScrim();

  @override
  Widget build(BuildContext context) {
    final base = DesignConstants.backgroundColor;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            base.withValues(alpha: 0),
            base.withValues(alpha: 0.85),
          ],
          stops: const [0.35, 1],
        ),
      ),
    );
  }
}
