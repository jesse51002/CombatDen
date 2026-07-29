import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/videos/data/video.dart';
import 'package:mobile_app/features/videos/presentation/widgets/sections/video_section_header.dart';
import 'package:mobile_app/features/videos/presentation/widgets/video_carousel_card.dart';

/// A tag section as a horizontally-scrolling row of cards — the body
/// `VideosFormat.carouselRows` ships today.
class VideoSectionRow extends StatelessWidget {
  const VideoSectionRow({
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
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: DesignConstants.screenHorizontalPadding,
          ),
          child: VideoSectionHeader(
            title: title,
            onViewAllTap: onViewAllTap,
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.symmetric(
            horizontal: DesignConstants.screenHorizontalPadding,
          ),
          child: Row(
            spacing: DesignConstants.spacingLarge,
            children: [
              for (final v in videos)
                VideoCarouselCard(
                  video: v,
                  onTap: () => onVideoTap?.call(v),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
