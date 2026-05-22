import 'package:flutter/material.dart';
import 'package:mobile_app/core/app_routes.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/profile/presentation/widgets/level_up_videos/level_up_videos_header.dart';
import 'package:mobile_app/features/videos/data/video.dart';
import 'package:mobile_app/features/videos/data/video_feed_repository.dart';
import 'package:mobile_app/features/videos/data/video_selectors.dart';
import 'package:mobile_app/features/videos/presentation/widgets/video_carousel_card.dart';

/// "Videos to level up" — the Education-bucket videos from the live feed, in
/// relevancy order, as a horizontal carousel on the profile/rank page. Hidden
/// until the feed loads (and when the tenant has no educational videos).
class LevelUpVideosSection extends StatelessWidget {
  const LevelUpVideosSection({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Video>>(
      future: VideoFeedRepository.instance.feed(),
      builder: (context, snapshot) {
        final ready =
            snapshot.connectionState == ConnectionState.done &&
            !snapshot.hasError;
        final videos = ready
            ? videosInScope(
                snapshot.data ?? const <Video>[],
                BigGroup.educational,
              )
            : const <Video>[];
        if (videos.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          spacing: DesignConstants.spacingLarge,
          children: [
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: DesignConstants.paddingBig,
              ),
              child: LevelUpVideosHeader(
                title: 'Videos to level up',
                onViewAll: () => Navigator.of(context).pushReplacementNamed(
                  AppRoutes.videos,
                  arguments: BigGroup.educational,
                ),
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(
                horizontal: DesignConstants.paddingBig,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: DesignConstants.spacingLarge,
                children: [
                  for (final video in videos) VideoCarouselCard(video: video),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
