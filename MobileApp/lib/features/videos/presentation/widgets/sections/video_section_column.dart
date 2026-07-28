import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/videos/data/video.dart';
import 'package:mobile_app/features/videos/presentation/widgets/sections/video_section_header.dart';
import 'package:mobile_app/features/videos/presentation/widgets/video_carousel_card.dart';
import 'package:mobile_app/features/videos/presentation/widgets/video_view_all_action.dart';

/// A tag section as one vertical column of width-filling cards, with
/// the "view all" action as a row closing the section.
///
/// No horizontal scrolling: every card in the section is reachable by
/// the same vertical gesture that moves the page.
class VideoSectionColumn extends StatelessWidget {
  const VideoSectionColumn({
    super.key,
    required this.title,
    required this.videos,
    this.onViewAllTap,
    this.onVideoTap,
  });

  final String title;
  final List<Video> videos;
  final VoidCallback? onViewAllTap;
  final ValueChanged<Video>? onVideoTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingLarge,
      children: [
        VideoSectionHeader(
          title: title,
          onViewAllTap: onViewAllTap,
          showViewAll: false,
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: DesignConstants.spacingLarge,
          children: [
            for (final v in videos)
              VideoCarouselCard(
                video: v,
                size: VideoCardSize.lg,
                onTap: () => onVideoTap?.call(v),
              ),
            VideoViewAllAction(
              onTap: onViewAllTap,
              style: VideoViewAllStyle.row,
            ),
          ],
        ),
      ],
    );
  }
}
