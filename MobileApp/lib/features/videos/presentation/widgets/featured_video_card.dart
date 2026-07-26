import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/videos/data/models/gym_video_card.dart';
import 'package:mobile_app/shared/widgets/buttons/app_primary_button.dart';
import 'package:mobile_app/shared/widgets/video_recc_card/creator_avatar.dart';
import 'package:mobile_app/shared/widgets/video_recc_card/video_recc_card.dart';

/// Big featured video — `VideoReccCard` wrapped in a card surface with a
/// full-width "Play" CTA underneath. Used for the very top hero on
/// `VideosScreen`.
class FeaturedVideoCard extends StatelessWidget {
  const FeaturedVideoCard({super.key, required this.card, this.onTap});

  final GymVideoCard card;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: DesignConstants.card,
        borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
      ),
      clipBehavior: Clip.hardEdge,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingLarge,
        children: [
          VideoReccCard(
            title: card.title,
            metaLabel: card.metaLabel,
            thumbnail: CachedNetworkImageProvider(card.thumbnailUrl),
            creatorPfp: creatorAvatarProvider(card.channelAvatarUrl),
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
              borderRadius: 100,
              onPressed: onTap,
            ),
          ),
        ],
      ),
    );
  }
}
