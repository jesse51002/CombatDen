import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/videos/presentation/layouts/videos_layout_data.dart';
import 'package:mobile_app/features/videos/presentation/layouts/videos_scope_tabs.dart';
import 'package:mobile_app/features/videos/presentation/widgets/featured_video_card.dart';
import 'package:mobile_app/features/videos/presentation/widgets/video_carousel_section.dart';
import 'package:mobile_app/features/videos/presentation/widgets/videos_feed_status.dart';

/// `VideosFormat.editorialStack` — no horizontal scrolling anywhere.
///
/// The hero bleeds to both edges like a cover, then every tag becomes a
/// vertical section of width-filling cards closed by a "view all" row.
/// Slower to browse, far better for a tenant whose content is long-form
/// and whose members read titles.
class VideosEditorialStack extends StatelessWidget {
  const VideosEditorialStack({super.key, required this.data});

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
            FeaturedVideoCard(
              video: featured,
              layout: FeaturedVideoLayout.bleed,
              onTap: () => data.onVideoTap(featured),
            ),
          for (final section in data.sections)
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: DesignConstants.screenHorizontalPadding,
              ),
              child: VideoCarouselSection(
                title: data.titleOf(section),
                videos: section.videos,
                layout: VideoSectionLayout.stack,
                onViewAllTap: () => data.onViewAll(section.tag),
                onVideoTap: data.onVideoTap,
              ),
            ),
          if (data.isEmpty)
            const VideosFeedStatus(kind: VideosFeedStatusKind.scopeEmpty),
        ],
      ),
    );
  }
}
