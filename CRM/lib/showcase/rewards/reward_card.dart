import 'package:flutter/material.dart';

import 'package:crm/showcase/showcase_assets.dart';
import 'package:crm/showcase/showcase_tokens.dart';
import 'package:crm/showcase/support/showcase_primary_button.dart';

// Reserve two lines of h2 (16px font, ~1.3 line height) so all cards have
// the same title block whether the title is one line or two.
const double _kRewardCardTitleHeight = 42;

/// Showcase clone of MobileApp's shared reward card. 3:2 image with a
/// brand-coloured price tag pinned to the top-right; below the image a
/// fixed-height title slot, the points cost, and a CTA whose label is
/// provided by the caller (e.g. "Use").
class RewardCard extends StatelessWidget {
  const RewardCard({
    super.key,
    this.imageAsset,
    this.imageUrl,
    required this.title,
    required this.priceLabel,
    required this.pointsCost,
    required this.buttonText,
    required this.onPressed,
  });

  /// Bundled fallback image (sample data); ignored when [imageUrl] is set.
  final String? imageAsset;

  /// Injected gym reward image (network URL); wins over [imageAsset].
  final String? imageUrl;
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
        color: ShowcaseTokens.card,
        borderRadius: BorderRadius.circular(ShowcaseTokens.radiusBig),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RewardImageHero(
            imageAsset: imageAsset,
            imageUrl: imageUrl,
            priceLabel: priceLabel,
          ),
          Padding(
            padding: const EdgeInsets.all(ShowcaseTokens.paddingSmall),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: ShowcaseTokens.spacingMedium,
              children: [
                SizedBox(
                  height: _kRewardCardTitleHeight,
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Text(
                      title,
                      style: ShowcaseTokens.h2,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                RewardPointsCost(pointsCost: pointsCost),
                ShowcasePrimaryButton(
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

/// 3:2 image with a brand-coloured price tag in the top-right.
class RewardImageHero extends StatelessWidget {
  const RewardImageHero({
    super.key,
    this.imageAsset,
    this.imageUrl,
    required this.priceLabel,
    this.borderRadius,
  });

  /// Bundled fallback image (sample data); ignored when [imageUrl] is set.
  final String? imageAsset;

  /// Injected gym reward image (network URL); wins over [imageAsset].
  final String? imageUrl;
  final String priceLabel;

  /// Optional rounded corners. Pass when used outside the card's own clip.
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final image = AspectRatio(
      aspectRatio: 1.5,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image(
            image: ShowcaseAsset.imageOrNetwork(imageUrl, imageAsset ?? ''),
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => ColoredBox(color: ShowcaseTokens.card),
          ),
          Positioned(
            top: ShowcaseTokens.spacingMedium,
            right: ShowcaseTokens.spacingMedium,
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
    final brand = ShowcaseTokens.primaryColor;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: ShowcaseTokens.spacingMedium,
        vertical: ShowcaseTokens.spacingTiny,
      ),
      decoration: BoxDecoration(
        color: brand,
        borderRadius: BorderRadius.circular(ShowcaseTokens.radiusSmall),
      ),
      child: Text(
        label,
        style: ShowcaseTokens.pSmall.copyWith(
          color: ShowcaseTokens.primaryButtonText,
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
      style: ShowcaseTokens.h2.copyWith(
        color: ShowcaseTokens.primaryColor,
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
