import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';

/// 3:2 reward image with a brand-orange price tag pinned top-right.
/// Shared by the admin reward card and the confirm dialog so the visual
/// identity carries from grid to detail (mirrors the member app).
class RewardImageHero extends StatelessWidget {
  final String imageAsset;
  final String? priceLabel;
  final BorderRadius? borderRadius;

  const RewardImageHero({
    super.key,
    required this.imageAsset,
    this.priceLabel,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final image = AspectRatio(
      aspectRatio: 1.5,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(imageAsset, fit: BoxFit.cover),
          if (priceLabel != null)
            Positioned(
              top: DesignConstants.spacingMedium,
              right: DesignConstants.spacingMedium,
              child: RewardPriceTag(label: priceLabel!),
            ),
        ],
      ),
    );
    if (borderRadius != null) {
      return ClipRRect(borderRadius: borderRadius!, child: image);
    }
    return image;
  }
}

class RewardPriceTag extends StatelessWidget {
  final String label;

  const RewardPriceTag({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignConstants.spacingMedium,
        vertical: DesignConstants.spacingTiny,
      ),
      decoration: BoxDecoration(
        color: DesignConstants.primaryColor,
        borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
      ),
      child: Text(
        label,
        style: DesignConstants.pSmallBold.copyWith(
          color: DesignConstants.backgroundColor,
        ),
      ),
    );
  }
}

/// Formats a points integer with thousand-separator commas: 1500 -> "1,500".
String formatRewardPoints(int n) {
  if (n < 1000) return '$n';
  final s = n.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return buf.toString();
}
