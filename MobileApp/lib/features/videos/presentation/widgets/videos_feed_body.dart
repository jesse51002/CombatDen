import 'package:flutter/material.dart';
import 'package:mobile_app/core/app_routes.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/videos/data/video.dart';
import 'package:mobile_app/features/videos/data/video_helpers.dart';
import 'package:mobile_app/features/videos/data/video_selectors.dart';
import 'package:mobile_app/features/videos/presentation/widgets/featured_video_card.dart';
import 'package:mobile_app/features/videos/presentation/widgets/video_carousel_section.dart';

/// The vertically-stacked feed below the topbar / tabs on `VideosScreen`,
/// derived live from the loaded [videos] and the active [scope]: a featured
/// hero, then one carousel per tag.
class VideosFeedBody extends StatelessWidget {
  const VideosFeedBody({
    super.key,
    required this.videos,
    required this.scope,
    required this.onVideoTap,
  });

  final List<Video> videos;
  final String? scope;
  final ValueChanged<Video> onVideoTap;

  @override
  Widget build(BuildContext context) {
    final featured = featuredVideo(videos, scope);
    final sections = tagSections(videos, scope);

    if (featured == null && sections.isEmpty) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: DesignConstants.spacingBig),
        child: Center(
          child: Text(
            'Nothing here yet.',
            style: DesignConstants.p.copyWith(color: DesignConstants.text2nd),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingBig,
      children: [
        if (featured != null)
          _PaddedSection(
            child: FeaturedVideoCard(
              video: featured,
              onTap: () => onVideoTap(featured),
            ),
          ),
        for (final section in sections)
          VideoCarouselSection(
            title: displayLabel(section.tag),
            videos: section.videos,
            onViewAllTap: () => Navigator.of(context).pushNamed(
              AppRoutes.videoTagList,
              arguments: section.tag,
            ),
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
