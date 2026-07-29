import 'package:flutter/material.dart';
import 'package:mobile_app/features/videos/presentation/layouts/videos_layout_data.dart';
import 'package:mobile_app/features/videos/presentation/widgets/video_category_tabs.dart';

/// The top-filter pills, wired to the layout payload.
///
/// Every layout goes through this rather than wiring
/// [VideoCategoryTabs] itself, so the filter behaves identically in all
/// five arrangements and only its axis changes.
class VideosScopeTabs extends StatelessWidget {
  const VideosScopeTabs({
    super.key,
    required this.data,
    this.axis = VideoCategoryTabsAxis.horizontal,
  });

  final VideosLayoutData data;
  final VideoCategoryTabsAxis axis;

  @override
  Widget build(BuildContext context) {
    return VideoCategoryTabs(
      tabs: data.tabLabels,
      selectedIndex: data.selectedTabIndex,
      axis: axis,
      onTabSelected: data.onTabSelected,
    );
  }
}
