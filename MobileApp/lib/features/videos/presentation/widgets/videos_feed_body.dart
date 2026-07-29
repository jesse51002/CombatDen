import 'package:flutter/material.dart';
import 'package:mobile_app/core/app_routes.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/videos/data/gym_video_selectors.dart';
import 'package:mobile_app/features/videos/data/models/gym_video_card.dart';
import 'package:mobile_app/features/videos/presentation/widgets/featured_video_card.dart';
import 'package:mobile_app/features/videos/presentation/widgets/video_carousel_section.dart';

/// The vertically-stacked feed below the topbar / tabs on `VideosScreen`,
/// derived from the loaded portal page [videos]: a featured hero, then one
/// carousel per genre. The page is already the selected tab's feed (the portal
/// filters by `video_type` server-side), so this just groups it by genre.
class VideosFeedBody extends StatelessWidget {
  const VideosFeedBody({
    super.key,
    required this.videos,
    required this.onVideoTap,
  });

  final List<GymVideoCard> videos;
  final ValueChanged<GymVideoCard> onVideoTap;

  @override
  Widget build(BuildContext context) {
    final featured = featuredCard(videos);
    final sections = genreSections(videos);

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
              card: featured,
              onTap: () => onVideoTap(featured),
            ),
          ),
        for (final section in sections)
          VideoCarouselSection(
            title: section.genre.label,
            videos: section.videos,
            onViewAllTap: () => Navigator.of(context).pushNamed(
              AppRoutes.videoTagList,
              arguments: section.genre,
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
