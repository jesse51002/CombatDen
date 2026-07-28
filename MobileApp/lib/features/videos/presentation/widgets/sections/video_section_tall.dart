import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/videos/data/video.dart';
import 'package:mobile_app/features/videos/presentation/widgets/sections/video_section_header.dart';
import 'package:mobile_app/features/videos/presentation/widgets/video_carousel_card.dart';

/// A tag section as one column of portrait cards, its title riding the
/// top of the first card instead of standing above the section.
///
/// The section reads as a run of full-height posters — the shape
/// members already know from the platforms this content comes from.
class VideoSectionTall extends StatelessWidget {
  const VideoSectionTall({
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
    final header = VideoSectionHeader(
      title: title,
      onViewAllTap: onViewAllTap,
      style: VideoSectionHeaderStyle.overlay,
    );
    if (videos.isEmpty) return header;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingLarge,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
          child: Stack(
            children: [
              _card(videos.first),
              Positioned(left: 0, right: 0, top: 0, child: header),
            ],
          ),
        ),
        for (final v in videos.skip(1)) _card(v),
      ],
    );
  }

  Widget _card(Video video) => VideoCarouselCard(
    video: video,
    size: VideoCardSize.tall,
    onTap: () => onVideoTap?.call(video),
  );
}
