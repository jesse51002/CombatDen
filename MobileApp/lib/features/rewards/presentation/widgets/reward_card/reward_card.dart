import 'package:flutter/material.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/reward_card/layouts/reward_card_hero.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/reward_card/layouts/reward_card_image_top.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/reward_card/layouts/reward_card_poster.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/reward_card/layouts/reward_card_thumb_left.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/reward_card/layouts/reward_card_tile.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/reward_card/reward_card_data.dart';

/// Shared reward card used by the Points Store and My Rewards.
///
/// The DATA arguments are unchanged and identical for every layout —
/// image, title, price label, points cost, and one action with its
/// label. [layout] is the only addition and is presentation: it picks
/// one of the arrangements in `reward_card/layouts/`, each of which
/// composes the same parts from `reward_card/parts/`.
///
/// Every layout must render every element: image, price tag, title,
/// points cost, and exactly one action. It may move them. It may not
/// drop one or add one. `test/rewards_invariants_test.dart` asserts this
/// per card, for every screen format.
class RewardCard extends StatelessWidget {
  const RewardCard({
    super.key,
    required this.imageUrl,
    required this.title,
    required this.priceLabel,
    required this.pointsCost,
    required this.buttonText,
    required this.onPressed,
    this.layout = RewardCardLayout.imageTop,
  });

  final String imageUrl;
  final String title;
  final String priceLabel;
  final int pointsCost;
  final String buttonText;
  final VoidCallback onPressed;
  final RewardCardLayout layout;

  @override
  Widget build(BuildContext context) {
    final data = RewardCardData(
      imageUrl: imageUrl,
      title: title,
      priceLabel: priceLabel,
      pointsCost: pointsCost,
      buttonText: buttonText,
      onPressed: onPressed,
    );

    return switch (layout) {
      RewardCardLayout.imageTop => RewardCardImageTop(data: data),
      RewardCardLayout.thumbLeft => RewardCardThumbLeft(data: data),
      RewardCardLayout.poster => RewardCardPoster(data: data),
      RewardCardLayout.tile => RewardCardTile(data: data),
      RewardCardLayout.hero => RewardCardHero(data: data),
    };
  }
}
