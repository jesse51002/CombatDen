import 'package:flutter/material.dart';
import 'package:mobile_app/core/app_slots.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/shared/widgets/api_image.dart';
import 'package:mobile_app/shared/widgets/branded_image.dart';

/// Belt icon + main rank name on top, sub-rank name below.
class RankHeader extends StatelessWidget {
  const RankHeader({
    super.key,
    required this.rankTitle,
    required this.rankSubtitle,
    required this.rankBadgeAsset,
  });

  final String rankTitle;
  final String rankSubtitle;
  final String rankBadgeAsset;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: DesignConstants.spacingLarge,
      children: [
        BrandedImage(
          slot: CombatDenSlots.rankBelt,
          fallback: ApiImage.rankAsset(rankBadgeAsset),
          width: 77,
          height: 50,
          fit: BoxFit.contain,
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          spacing: DesignConstants.spacingSmall,
          children: [
            Text(rankTitle, style: DesignConstants.h1),
            Text(
              rankSubtitle,
              style: DesignConstants.h2.copyWith(
                color: DesignConstants.text2nd,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
