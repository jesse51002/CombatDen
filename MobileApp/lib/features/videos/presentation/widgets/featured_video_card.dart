import 'package:flutter/material.dart';
import 'package:mobile_app/core/constants/design_constants.dart';
import 'package:mobile_app/features/videos/data/mock_videos.dart';
import 'package:mobile_app/shared/widgets/buttons/app_primary_button.dart';
import 'package:mobile_app/shared/widgets/video_recc_card/video_recc_card.dart';

/// Big featured video — `VideoReccCard` wrapped in a card surface with a
/// full-width "Play" CTA underneath. Used both for the very top hero on
/// `VideosScreen` and for the "Technique of the Day" block.
class FeaturedVideoCard extends StatelessWidget {
  const FeaturedVideoCard({super.key, required this.video, this.onTap});

  final MockVideo video;
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
            title: video.title,
            metaLabel: video.metaLabel,
            thumbnailAsset: video.thumbnailAsset,
            creatorPfpAsset: video.creatorPfpAsset,
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
