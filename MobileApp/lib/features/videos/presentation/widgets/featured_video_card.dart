import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/videos/data/video.dart';
import 'package:mobile_app/shared/widgets/buttons/app_primary_button.dart';
import 'package:mobile_app/shared/widgets/video_recc_card/video_recc_card.dart';

/// How the featured hero meets the screen edge.
enum FeaturedVideoLayout {
  /// A rounded card sitting inside the screen gutter. Shipped.
  card,

  /// Square-cornered and edge-to-edge, so the hero reads as a poster
  /// the page starts with. The caller drops its horizontal inset.
  bleed,
}

/// Big featured video — `VideoReccCard` wrapped in a card surface with a
/// full-width "Play" CTA underneath. Used for the very top hero on
/// `VideosScreen`.
class FeaturedVideoCard extends StatelessWidget {
  const FeaturedVideoCard({
    super.key,
    required this.video,
    this.layout = FeaturedVideoLayout.card,
    this.onTap,
  });

  final Video video;
  final FeaturedVideoLayout layout;
  final VoidCallback? onTap;

  // The CTA's own pill radius, unchanged from the shipped hero.
  static const double _kPlayRadius = 100;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: DesignConstants.card,
        borderRadius: layout == FeaturedVideoLayout.bleed
            ? BorderRadius.zero
            : BorderRadius.circular(DesignConstants.radiusBig),
      ),
      clipBehavior: Clip.hardEdge,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingLarge,
        children: [
          VideoReccCard(
            title: video.title,
            metaLabel: video.metaLabel,
            thumbnail: CachedNetworkImageProvider(video.thumbnailUrl),
            creatorPfp: CachedNetworkImageProvider(video.channelAvatarUrl),
            roundThumbnail: false,
            onTap: onTap,
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              DesignConstants.paddingBig,
              0,
              DesignConstants.paddingBig,
              DesignConstants.spacingLarge,
            ),
            child: AppPrimaryButton(
              text: 'Play',
              fullWidth: true,
              borderRadius: _kPlayRadius,
              onPressed: onTap,
            ),
          ),
        ],
      ),
    );
  }
}
