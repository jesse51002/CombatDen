import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/videos/presentation/layouts/videos_layout_data.dart';
import 'package:mobile_app/features/videos/presentation/layouts/videos_scope_tabs.dart';
import 'package:mobile_app/features/videos/presentation/widgets/featured_video_card.dart';
import 'package:mobile_app/features/videos/presentation/widgets/video_carousel_section.dart';
import 'package:mobile_app/features/videos/presentation/widgets/videos_feed_status.dart';

/// `VideosFormat.carouselRows` — the arrangement that ships today.
///
/// Pill strip, a featured hero in the screen gutter, then one
/// horizontally-scrolling row per tag. Reproduces the previous
/// `VideosScreen` body value for value, so a tenant with no layout slot
/// sees no change.
class VideosCarouselRows extends StatelessWidget {
  const VideosCarouselRows({super.key, required this.data});

  final VideosLayoutData data;

  @override
  Widget build(BuildContext context) {
    final featured = data.featured;
    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingBig,
        children: [
          VideosScopeTabs(data: data),
          if (featured != null)
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: DesignConstants.screenHorizontalPadding,
              ),
              child: FeaturedVideoCard(
                video: featured,
                onTap: () => data.onVideoTap(featured),
              ),
            ),
          for (final section in data.sections)
            VideoCarouselSection(
              title: data.titleOf(section),
              videos: section.videos,
              onViewAllTap: () => data.onViewAll(section.tag),
              onVideoTap: data.onVideoTap,
            ),
          if (data.isEmpty)
            const VideosFeedStatus(kind: VideosFeedStatusKind.scopeEmpty),
        ],
      ),
    );
  }
}
