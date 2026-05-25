import 'package:mobile_app/features/videos/data/video.dart';

/// Pure derivations over a loaded video feed. No fetching, no caching — given
/// a `List<Video>` and (where relevant) a big-group `scope` string, return
/// what each surface renders. `scope == null` means the "All" top filter.
///
/// The coarse `big_groups` and fine-grained `tags` are plain server strings;
/// this file owns no vocabulary — scopes and carousels derive from whatever
/// the feed actually contains.

/// Tag wire values the recommendation heuristics below special-case. Plain
/// server strings, not a closed vocabulary — just the few referenced here.
const String _kEducational = 'educational';
const String _kAnalysis = 'analysis';

/// Sorts by backend relevancy (relevanceIndex asc, 0 = top hit), with view
/// count as the secondary tiebreak. The single source of ordering for every
/// video list/pick.
List<Video> sortByRelevance(Iterable<Video> videos) {
  final list = videos.toList();
  list.sort((a, b) {
    final byRelevance = a.relevanceIndex.compareTo(b.relevanceIndex);
    if (byRelevance != 0) return byRelevance;
    return (b.viewCount ?? -1).compareTo(a.viewCount ?? -1);
  });
  return list;
}

/// Videos belonging to [scope] (all videos when [scope] is null), in
/// relevancy order.
List<Video> videosInScope(List<Video> videos, String? scope) => sortByRelevance(
  scope == null ? videos : videos.where((v) => v.bigGroups.contains(scope)),
);

/// The distinct big-group strings present in the feed, in first-appearance
/// order over the relevancy-sorted videos. Drives the home page's top-filter
/// tabs, so they reflect whatever coarse groups the server actually sent.
List<String> bigGroupsInFeed(List<Video> videos) {
  final seen = <String>{};
  final groups = <String>[];
  for (final video in sortByRelevance(videos)) {
    for (final group in video.bigGroups) {
      if (seen.add(group)) groups.add(group);
    }
  }
  return groups;
}

/// The hero video: the top-ranked (most relevant) video in scope.
Video? featuredVideo(List<Video> videos, String? scope) =>
    _firstOrNull(videosInScope(videos, scope));

/// One carousel per fine-grained tag present in [scope], ordered by the tag's
/// first appearance across the relevancy-sorted feed. Each video appears in
/// exactly one carousel — the first eligible tag it carries in that order — so
/// a multi-tagged video clusters into the earliest tag rather than fragmenting
/// across rows. Within each carousel videos stay in relevancy order
/// ([videosInScope] is already sorted). Tags are derived from the in-scope
/// videos themselves, so an entertainment-only carousel never shows under
/// Education; tags left with no videos after assignment are skipped too.
List<({String tag, List<Video> videos})> tagSections(
  List<Video> videos,
  String? scope,
) {
  final inScope = videosInScope(videos, scope);

  // Distinct tags present in scope, in first-appearance (relevancy) order.
  final seen = <String>{};
  final eligibleTags = <String>[];
  for (final video in inScope) {
    for (final tag in video.tags) {
      if (seen.add(tag)) eligibleTags.add(tag);
    }
  }

  // Claim each video for the first eligible tag it carries.
  final claimed = {for (final tag in eligibleTags) tag: <Video>[]};
  for (final video in inScope) {
    for (final tag in eligibleTags) {
      if (video.tags.contains(tag)) {
        claimed[tag]!.add(video);
        break;
      }
    }
  }

  return [
    for (final tag in eligibleTags)
      if (claimed[tag]!.isNotEmpty)
        (tag: tag, videos: List<Video>.unmodifiable(claimed[tag]!)),
  ];
}

/// Post-class "Drill of the Day": the 2nd-ranked educational video so it
/// doesn't echo a featured one; falls back to the top analysis, then any.
Video? drillOfTheDay(List<Video> videos) {
  final ranked = sortByRelevance(videos);
  final educational = ranked
      .where((v) => v.tags.contains(_kEducational))
      .toList(growable: false);
  if (educational.length >= 2) return educational[1];
  return _firstWithTag(ranked, _kAnalysis) ?? _firstOrNull(ranked);
}

/// Post-booking "Video Before Class": top-ranked educational/analysis.
Video? videoBeforeClass(List<Video> videos) {
  final ranked = sortByRelevance(videos);
  return _firstWithTag(ranked, _kEducational) ??
      _firstWithTag(ranked, _kAnalysis) ??
      _firstOrNull(ranked);
}

Video? _firstOrNull(Iterable<Video> videos) =>
    videos.isEmpty ? null : videos.first;

Video? _firstWithTag(Iterable<Video> videos, String tag) {
  for (final v in videos) {
    if (v.tags.contains(tag)) return v;
  }
  return null;
}
