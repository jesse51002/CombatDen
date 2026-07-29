import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/videos/presentation/layouts/videos_layout_data.dart';
import 'package:mobile_app/features/videos/presentation/layouts/videos_scope_tabs.dart';
import 'package:mobile_app/features/videos/presentation/widgets/featured_video_card.dart';
import 'package:mobile_app/features/videos/presentation/widgets/video_carousel_section.dart';
import 'package:mobile_app/features/videos/presentation/widgets/video_category_tabs.dart';
import 'package:mobile_app/features/videos/presentation/widgets/videos_feed_status.dart';

/// `VideosFormat.tagRail` — the filter leaves the top and becomes a
/// rail down the left, pinned so it stays reachable the whole way down.
///
/// Content is one narrower column beside it. This is the value for a
/// tenant whose feed carries enough groups that a pill strip across the
/// top stops being readable.
class VideosTagRail extends StatelessWidget {
  const VideosTagRail({super.key, required this.data});

  final VideosLayoutData data;

  static const double _kRailWidth = 112;

  @override
  Widget build(BuildContext context) {
    return SliverCrossAxisGroup(
      slivers: [
        SliverConstrainedCrossAxis(
          maxExtent: _kRailWidth,
          sliver: SliverPersistentHeader(
            pinned: true,
            delegate: _Rail(data),
          ),
        ),
        SliverCrossAxisExpanded(
          flex: 1,
          sliver: SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.only(
                left: DesignConstants.spacingMedium,
                right: DesignConstants.screenHorizontalPadding,
              ),
              child: _Content(data: data),
            ),
          ),
        ),
      ],
    );
  }
}

/// The column beside the rail: hero, then one section per tag.
class _Content extends StatelessWidget {
  const _Content({required this.data});

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
            layout: VideoSectionLayout.stack,
            onViewAllTap: () => data.onViewAll(section.tag),
            onVideoTap: data.onVideoTap,
          ),
        if (data.isEmpty)
          const VideosFeedStatus(kind: VideosFeedStatusKind.scopeEmpty),
      ],
    );
  }
}

/// The pinned rail itself. Fixed band, pills scrolling inside it, so a
/// tenant with many groups lengthens the rail's scroll rather than the
/// page's chrome.
class _Rail extends SliverPersistentHeaderDelegate {
  const _Rail(this.data);

  final VideosLayoutData data;

  static const double _kExtent = 240;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) {
    // The band must fill [_kExtent] whatever the pills add up to: a
    // persistent header measures its child, and a short rail that
    // reported its own height would leave the header claiming more
    // layout than it paints.
    return ColoredBox(
      color: DesignConstants.backgroundColor,
      child: Align(
        alignment: Alignment.topCenter,
        child: VideosScopeTabs(
          data: data,
          axis: VideoCategoryTabsAxis.vertical,
        ),
      ),
    );
  }

  @override
  double get maxExtent => _kExtent;

  @override
  double get minExtent => _kExtent;

  @override
  bool shouldRebuild(covariant _Rail oldDelegate) => true;
}
