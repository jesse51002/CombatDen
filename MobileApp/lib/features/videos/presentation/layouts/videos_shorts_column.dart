import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/videos/presentation/layouts/videos_layout_data.dart';
import 'package:mobile_app/features/videos/presentation/layouts/videos_scope_tabs.dart';
import 'package:mobile_app/features/videos/presentation/widgets/featured_video_card.dart';
import 'package:mobile_app/features/videos/presentation/widgets/video_carousel_section.dart';
import 'package:mobile_app/features/videos/presentation/widgets/videos_feed_status.dart';

/// `VideosFormat.shortsColumn` — one column of portrait cards.
///
/// The tag name rides the top of its first card instead of standing
/// above the section, so the page reads as one continuous run of
/// posters: the shape members already use for this content elsewhere.
class VideosShortsColumn extends StatelessWidget {
  const VideosShortsColumn({super.key, required this.data});

  final VideosLayoutData data;

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingBig,
        children: [
          VideosScopeTabs(data: data),
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: DesignConstants.screenHorizontalPadding,
            ),
            child: _Column(data: data),
          ),
        ],
      ),
    );
  }
}

/// The poster run itself, inside the screen gutter.
class _Column extends StatelessWidget {
  const _Column({required this.data});

  final VideosLayoutData data;

  @override
  Widget build(BuildContext context) {
    final featured = data.featured;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingBig,
      children: [
        if (featured != null)
          FeaturedVideoCard(
            video: featured,
            onTap: () => data.onVideoTap(featured),
          ),
        for (final section in data.sections)
          VideoCarouselSection(
            title: data.titleOf(section),
            videos: section.videos,
            layout: VideoSectionLayout.tall,
            onViewAllTap: () => data.onViewAll(section.tag),
            onVideoTap: data.onVideoTap,
          ),
        if (data.isEmpty)
          const VideosFeedStatus(kind: VideosFeedStatusKind.scopeEmpty),
      ],
    );
  }
}
