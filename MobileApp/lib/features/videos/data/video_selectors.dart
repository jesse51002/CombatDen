import 'package:mobile_app/features/videos/data/video.dart';

/// Pure derivations over a loaded video feed. No fetching, no caching — given
/// a `List<Video>` and (where relevant) a [BigGroup] scope, return what each
/// surface renders. `scope == null` means the "All" top filter.

/// The tags that map to [BigGroup.educational]. Mirrors the server mapping in
/// `../VideoService/schema/big_group.py`; every other tag is entertainment.
const Set<VideoTag> _kEducationalTags = {
  VideoTag.educational,
  VideoTag.tutorial,
  VideoTag.informative,
};

BigGroup bigGroupOfTag(VideoTag tag) =>
    _kEducationalTags.contains(tag) ? BigGroup.educational : BigGroup.entertainment;

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
List<Video> videosInScope(List<Video> videos, BigGroup? scope) => sortByRelevance(
  scope == null ? videos : videos.where((v) => v.bigGroups.contains(scope)),
);

/// The hero video: the top-ranked (most relevant) video in scope.
Video? featuredVideo(List<Video> videos, BigGroup? scope) =>
    _firstOrNull(videosInScope(videos, scope));

/// One carousel per fine-grained tag present in scope, ordered by the
/// [VideoTag] declaration order. Within each carousel videos stay in relevancy
/// order ([videosInScope] is already sorted). Tags whose own big group differs
/// from [scope] are skipped, so an entertainment-tag carousel never shows
/// under Education.
List<({VideoTag tag, List<Video> videos})> tagSections(
  List<Video> videos,
  BigGroup? scope,
) {
  final inScope = videosInScope(videos, scope);
  final sections = <({VideoTag tag, List<Video> videos})>[];
  for (final tag in VideoTag.values) {
    if (tag == VideoTag.unknown) continue;
    if (scope != null && bigGroupOfTag(tag) != scope) continue;
    final tagged = inScope
        .where((v) => v.tags.contains(tag))
        .toList(growable: false);
    if (tagged.isNotEmpty) sections.add((tag: tag, videos: tagged));
  }
  return sections;
}

/// "Technique of the Day": top-ranked tutorial, then educational, then any.
Video? techniqueOfTheDay(List<Video> videos) {
  final ranked = sortByRelevance(videos);
  return _firstWithTag(ranked, VideoTag.tutorial) ??
      _firstWithTag(ranked, VideoTag.educational) ??
      _firstOrNull(ranked);
}

/// Post-class "Drill of the Day": the 2nd-ranked tutorial so it doesn't echo
/// Technique of the Day; falls back to the top educational, then any.
Video? drillOfTheDay(List<Video> videos) {
  final ranked = sortByRelevance(videos);
  final tutorials = ranked
      .where((v) => v.tags.contains(VideoTag.tutorial))
      .toList(growable: false);
  if (tutorials.length >= 2) return tutorials[1];
  return _firstWithTag(ranked, VideoTag.educational) ?? _firstOrNull(ranked);
}

/// Post-booking "Video Before Class": top-ranked educational/informative.
Video? videoBeforeClass(List<Video> videos) {
  final ranked = sortByRelevance(videos);
  return _firstWithTag(ranked, VideoTag.educational) ??
      _firstWithTag(ranked, VideoTag.informative) ??
      _firstOrNull(ranked);
}

Video? _firstOrNull(Iterable<Video> videos) =>
    videos.isEmpty ? null : videos.first;

Video? _firstWithTag(Iterable<Video> videos, VideoTag tag) {
  for (final v in videos) {
    if (v.tags.contains(tag)) return v;
  }
  return null;
}
