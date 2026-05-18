import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/videos/data/mock_videos.dart';
import 'package:mobile_app/features/videos/presentation/widgets/featured_video_card.dart';
import 'package:mobile_app/features/videos/presentation/widgets/video_carousel_section.dart';

/// The vertically-stacked feed of sections shown below the topbar / tabs
/// on `VideosScreen`. Pulled out so the screen file stays focused on
/// orchestration (state, scroll, nav).
class VideosFeedBody extends StatelessWidget {
  const VideosFeedBody({super.key, required this.onVideoTap});

  final ValueChanged<MockVideo> onVideoTap;

  @override
  Widget build(BuildContext context) {
    final yourNextWatch = mockVideos
        .where((v) => v.category == 'Your Next Watch')
        .toList(growable: false);
    final levelUp = mockVideos
        .where((v) => v.category == 'Level up your skills')
        .toList(growable: false);
    final fightsHighlights = [
      ...mockVideos.where((v) => v.category == 'Fights Highlights'),
      ...mockVideos.where((v) => v.category == 'Fights Highlights'),
    ];
    final realityShow = [mockFeaturedVideo, mockFeaturedVideo];
    final skits = [
      ...mockVideos.where((v) => v.category == 'Martial Arts Skits'),
      ...mockVideos.where((v) => v.category == 'Martial Arts Skits'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingBig,
      children: [
        _PaddedSection(
          child: FeaturedVideoCard(
            video: mockFeaturedVideo,
            onTap: () => onVideoTap(mockFeaturedVideo),
          ),
        ),
        VideoCarouselSection(
          title: 'Your Next Watch',
          videos: yourNextWatch,
          onViewAllTap: () => debugPrint('TODO: view all Your Next Watch'),
          onVideoTap: onVideoTap,
        ),
        VideoCarouselSection(
          title: 'Level up your skills',
          videos: levelUp,
          onViewAllTap: () =>
              debugPrint('TODO: view all Level up your skills'),
          onVideoTap: onVideoTap,
        ),
        _PaddedSection(
          child: _TitledFeatured(
            title: 'Technique of the Day',
            video: mockTechniqueOfTheDay,
            onTap: () => onVideoTap(mockTechniqueOfTheDay),
          ),
        ),
        VideoCarouselSection(
          title: 'Fights Highlights',
          videos: fightsHighlights,
          onViewAllTap: () => debugPrint('TODO: view all Fights Highlights'),
          onVideoTap: onVideoTap,
        ),
        VideoCarouselSection(
          title: 'Reality Style Fighting Show',
          videos: realityShow,
          onViewAllTap: () =>
              debugPrint('TODO: view all Reality Style Fighting Show'),
          onVideoTap: onVideoTap,
        ),
        VideoCarouselSection(
          title: 'Martial Arts Skits',
          videos: skits,
          onViewAllTap: () => debugPrint('TODO: view all Martial Arts Skits'),
          onVideoTap: onVideoTap,
        ),
      ],
    );
  }
}

class _PaddedSection extends StatelessWidget {
  const _PaddedSection({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: DesignConstants.screenHorizontalPadding,
      ),
      child: child,
    );
  }
}

class _TitledFeatured extends StatelessWidget {
  const _TitledFeatured({
    required this.title,
    required this.video,
    required this.onTap,
  });

  final String title;
  final MockVideo video;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingLarge,
      children: [
        Text(title, style: DesignConstants.h2),
        FeaturedVideoCard(video: video, onTap: onTap),
      ],
    );
  }
}
