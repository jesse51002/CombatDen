import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/videos/presentation/layouts/videos_layout_data.dart';
import 'package:mobile_app/features/videos/presentation/layouts/videos_scope_tabs.dart';
import 'package:mobile_app/features/videos/presentation/widgets/featured_video_card.dart';
import 'package:mobile_app/features/videos/presentation/widgets/video_carousel_section.dart';
import 'package:mobile_app/features/videos/presentation/widgets/videos_feed_status.dart';

/// `VideosFormat.mosaic` — the densest of the five.
///
/// The filter pins to the top so it stays reachable through a long
/// page, the hero spans the full width, and each tag becomes a
/// two-column tile grid under an inline band divider.
class VideosMosaic extends StatelessWidget {
  const VideosMosaic({super.key, required this.data});

  final VideosLayoutData data;

  @override
  Widget build(BuildContext context) {
    final featured = data.featured;
    return SliverMainAxisGroup(
      slivers: [
        SliverPersistentHeader(pinned: true, delegate: _PinnedTabs(data)),
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: DesignConstants.screenHorizontalPadding,
            ),
            child: Column(
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
                    layout: VideoSectionLayout.grid,
                    onViewAllTap: () => data.onViewAll(section.tag),
                    onVideoTap: data.onVideoTap,
                  ),
                if (data.isEmpty)
                  const VideosFeedStatus(
                    kind: VideosFeedStatusKind.scopeEmpty,
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Holds the pill strip against the top of the viewport. The strip
/// scrolls sideways inside a fixed band, so the tenant's group count
/// never changes the band's height.
class _PinnedTabs extends SliverPersistentHeaderDelegate {
  const _PinnedTabs(this.data);

  final VideosLayoutData data;

  static const double _kExtent = 76;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) {
    return ColoredBox(
      color: DesignConstants.backgroundColor,
      child: Center(child: VideosScopeTabs(data: data)),
    );
  }

  @override
  double get maxExtent => _kExtent;

  @override
  double get minExtent => _kExtent;

  @override
  bool shouldRebuild(covariant _PinnedTabs oldDelegate) => true;
}
