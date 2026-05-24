import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/videos/data/video.dart';
import 'package:mobile_app/features/videos/data/video_helpers.dart';

/// Compact video card used inside the horizontally-scrolling tag sections.
class VideoCarouselCard extends StatelessWidget {
  const VideoCarouselCard({super.key, required this.video, this.onTap});

  final Video video;
  final VoidCallback? onTap;

  static const double _kCardWidth = 258;
  static const double _kThumbHeight = 145;
  static const double _kPfpSize = 35;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: _kCardWidth,
        child: Container(
          decoration: BoxDecoration(
            color: DesignConstants.card,
            borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
          ),
          clipBehavior: Clip.hardEdge,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: DesignConstants.spacingLarge,
            children: [
              SizedBox(
                height: _kThumbHeight,
                child: Image(
                  image: CachedNetworkImageProvider(video.thumbnailUrl),
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) =>
                      ColoredBox(color: DesignConstants.card),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  DesignConstants.spacingMedium,
                  0,
                  DesignConstants.spacingMedium,
                  DesignConstants.spacingLarge,
                ),
                child: _Info(video: video),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Info extends StatelessWidget {
  const _Info({required this.video});

  final Video video;

  @override
  Widget build(BuildContext context) {
    final views = formatViewCount(video.viewCount);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        ClipOval(
          child: Image(
            image: CachedNetworkImageProvider(video.channelAvatarUrl),
            width: VideoCarouselCard._kPfpSize,
            height: VideoCarouselCard._kPfpSize,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => SizedBox(
              width: VideoCarouselCard._kPfpSize,
              height: VideoCarouselCard._kPfpSize,
              child: ColoredBox(color: DesignConstants.card),
            ),
          ),
        ),
        Expanded(
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: DesignConstants.spacingMedium,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: DesignConstants.spacingMedium,
              children: [
                Text(
                  video.title,
                  style: DesignConstants.p,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  views.isEmpty ? video.channelName : '$views views',
                  style: DesignConstants.pSmall.copyWith(
                    color: DesignConstants.text2nd,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
