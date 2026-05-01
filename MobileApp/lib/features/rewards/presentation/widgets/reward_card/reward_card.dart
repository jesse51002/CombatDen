import 'package:flutter/material.dart';
import 'package:mobile_app/core/constants/design_constants.dart';
import 'package:mobile_app/shared/widgets/brand_image.dart';
import 'package:mobile_app/shared/widgets/buttons/app_primary_button.dart';

// Reserve two lines of h2 (16px font, ~1.3 line height) so all cards have
// the same title block whether the title is one line or two.
const double _kCardTitleHeight = 42;

/// Shared reward card used by both the Points Store and My Rewards grids.
/// 3:2 image with a brand-orange price tag pinned to the top-right; below
/// the image a fixed-height title slot, the points cost, and a CTA whose
/// label is provided by the caller (e.g. "Redeem" vs "Use").
class RewardCard extends StatelessWidget {
  const RewardCard({
    super.key,
    required this.imageAsset,
    required this.title,
    required this.priceLabel,
    required this.pointsCost,
    required this.buttonText,
    required this.onPressed,
  });

  final String imageAsset;
  final String title;
  final String priceLabel;
  final int pointsCost;
  final String buttonText;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: DesignConstants.card,
        borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RewardImageHero(
            imageAsset: imageAsset,
            priceLabel: priceLabel,
          ),
          Padding(
            padding: EdgeInsets.all(DesignConstants.paddingSmall),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: DesignConstants.spacingMedium,
              children: [
                SizedBox(
                  height: _kCardTitleHeight,
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Text(
                      title,
                      style: DesignConstants.h2,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                RewardPointsCost(pointsCost: pointsCost),
                AppPrimaryButton(
                  text: buttonText,
                  fullWidth: true,
                  onPressed: onPressed,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 3:2 image with a brand-orange price tag in the top-right. Used by the
/// reward card and by the redeem dialog so the visual identity carries
/// from list to detail.
class RewardImageHero extends StatelessWidget {
  const RewardImageHero({
    super.key,
    required this.imageAsset,
    required this.priceLabel,
    this.borderRadius,
  });

  final String imageAsset;
  final String priceLabel;

  /// Optional rounded corners. Pass when used outside the card's own clip
  /// (e.g. inside the dialog) so the image visibly rounds.
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final image = AspectRatio(
      aspectRatio: 1.5,
      child: Stack(
        fit: StackFit.expand,
        children: [
          BrandImage.asset(imageAsset, fit: BoxFit.cover),
          Positioned(
            top: DesignConstants.spacingMedium,
            right: DesignConstants.spacingMedium,
            child: RewardPriceTag(label: priceLabel),
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
  const RewardPriceTag({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final brand = DesignConstants.of(context).primaryColor;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: DesignConstants.spacingMedium,
        vertical: DesignConstants.spacingTiny,
      ),
      decoration: BoxDecoration(
        color: brand,
        borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
      ),
      child: Text(
        label,
        style: DesignConstants.pSmall.copyWith(
          color: DesignConstants.text,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class RewardPointsCost extends StatelessWidget {
  const RewardPointsCost({super.key, required this.pointsCost});

  final int pointsCost;

  @override
  Widget build(BuildContext context) {
    return Text(
      '${formatRewardPoints(pointsCost)} pts',
      style: DesignConstants.h2.copyWith(
        color: DesignConstants.of(context).primaryColor,
      ),
      textAlign: TextAlign.center,
    );
  }
}

/// Formats a points integer with thousand-separator commas.
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
