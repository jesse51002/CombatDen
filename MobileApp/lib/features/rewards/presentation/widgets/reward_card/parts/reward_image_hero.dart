import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/reward_card/parts/reward_price_tag.dart';

/// The shipped 3:2 reward image ratio.
const double kRewardImageRatio = 1.5;

/// A reward's image, with its price tag pinned to the top-right corner.
///
/// Used by every card layout and by the redeem dialog, so the visual
/// identity carries from list to detail.
///
/// [aspectRatio] and [showPriceTag] are PRESENTATION knobs:
/// * `aspectRatio: null` fills whatever height the parent gives it —
///   used by the poster deck, where the deck's height decides the
///   poster's, not the other way round.
/// * `showPriceTag: false` means the CALLER renders the one
///   [RewardPriceTag] itself (the row layout puts it inline beside the
///   title). It never means the card loses its tag — the layout
///   invariant test counts exactly one tag per card.
class RewardImageHero extends StatelessWidget {
  const RewardImageHero({
    super.key,
    required this.imageUrl,
    required this.priceLabel,
    this.aspectRatio = kRewardImageRatio,
    this.showPriceTag = true,
    this.borderRadius,
  });

  final String imageUrl;
  final String priceLabel;
  final double? aspectRatio;
  final bool showPriceTag;

  /// Optional rounded corners. Pass when used outside the card's own clip
  /// (e.g. inside the dialog) so the image visibly rounds.
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    Widget image = Stack(
      fit: StackFit.expand,
      children: [
        Image(
          image: CachedNetworkImageProvider(imageUrl),
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => ColoredBox(color: DesignConstants.card),
        ),
        if (showPriceTag)
          Positioned(
            top: DesignConstants.spacingMedium,
            right: DesignConstants.spacingMedium,
            child: RewardPriceTag(label: priceLabel),
          ),
      ],
    );
    if (aspectRatio != null) {
      image = AspectRatio(aspectRatio: aspectRatio!, child: image);
    }
    if (borderRadius != null) {
      return ClipRRect(borderRadius: borderRadius!, child: image);
    }
    return image;
  }
}
