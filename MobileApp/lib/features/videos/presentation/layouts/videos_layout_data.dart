import 'package:flutter/widgets.dart';
import 'package:mobile_app/features/videos/data/video.dart';
import 'package:mobile_app/features/videos/data/video_helpers.dart';
import 'package:mobile_app/features/videos/data/video_selectors.dart';

/// One tag's videos, in relevancy order.
typedef VideoTagSection = ({String tag, List<Video> videos});

/// Everything a videos layout renders, derived once so all five values
/// are handed the identical payload.
///
/// This is where the arrangement-only invariant is made structural: a
/// layout cannot reach past this object, so it cannot fetch, re-sort,
/// or filter anything. Choosing a format changes where these land, not
/// what they are.
class VideosLayoutData {
  const VideosLayoutData({
    required this.tabLabels,
    required this.selectedTabIndex,
    required this.onTabSelected,
    required this.featured,
    required this.sections,
    required this.onVideoTap,
    required this.onViewAll,
  });

  /// Derives the whole payload from a loaded feed and the active top
  /// filter. `scope == null` is the "All" tab.
  factory VideosLayoutData.fromFeed({
    required List<Video> videos,
    required String? scope,
    required ValueChanged<String?> onScopeSelected,
    required ValueChanged<Video> onVideoTap,
    required ValueChanged<String> onViewAll,
  }) {
    final scopes = bigGroupsInFeed(videos);
    final tabScopes = <String?>[null, ...scopes];
    var index = tabScopes.indexOf(scope);
    if (index < 0) index = 0;
    final active = tabScopes[index];

    return VideosLayoutData(
      tabLabels: ['All', ...scopes.map(displayLabel)],
      selectedTabIndex: index,
      onTabSelected: (i) => onScopeSelected(tabScopes[i]),
      featured: featuredVideo(videos, active),
      sections: tagSections(videos, active),
      onVideoTap: onVideoTap,
      onViewAll: onViewAll,
    );
  }

  /// "All" plus one label per `big_group` the loaded feed carries.
  final List<String> tabLabels;
  final int selectedTabIndex;
  final ValueChanged<int> onTabSelected;

  /// The hero: the most relevant video in the active filter.
  final Video? featured;

  /// One entry per tag present in the active filter.
  final List<VideoTagSection> sections;

  final ValueChanged<Video> onVideoTap;

  /// Opens one tag's full list. Called with the tag's wire value.
  final ValueChanged<String> onViewAll;

  /// The active filter holds nothing to show.
  bool get isEmpty => featured == null && sections.isEmpty;

  /// The title a section renders, formatted from its wire tag.
  String titleOf(VideoTagSection section) => displayLabel(section.tag);
}
