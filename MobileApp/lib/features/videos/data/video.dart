import 'package:mobile_app/features/videos/data/video_helpers.dart';

/// A single video as served by the VideoService
/// (`GET /gyms/{gymId}/videos` → `VideoCard`). Field names mirror the
/// API so the JSON parse stays mechanical.
///
/// See `../VideoService/schema/video_feed.py` for the source contract.
class Video {
  const Video({
    required this.url,
    required this.title,
    required this.thumbnailUrl,
    required this.channelName,
    required this.channelUrl,
    required this.channelAvatarUrl,
    required this.viewCount,
    required this.relevanceIndex,
    required this.tags,
    required this.bigGroups,
    this.isGood,
  });

  final String url;
  final String title;
  final String thumbnailUrl;
  final String channelName;
  final String channelUrl;
  final String channelAvatarUrl;

  /// The "views" label; null when the channel hides its stats.
  final int? viewCount;

  /// Backend relevancy rank: 0 = top hit, lower is more relevant. The primary
  /// sort key for every list (view count is the secondary tiebreak).
  final int relevanceIndex;

  /// The video's genre. The API sends a single `tag` string (lowercase wire
  /// value); we hold it as a one-element list so the per-tag carousel grouping
  /// stays list-based. Empty until the feed is classified. Taken verbatim — the
  /// app owns no tag vocabulary.
  final List<String> tags;

  /// Coarse grouping the server derived from the tag (e.g. `educational` /
  /// `entertainment`); the home page's top-level filter. The API sends a single
  /// `big_group` string, held as a one-element list. Taken verbatim.
  final List<String> bigGroups;

  /// The classifier's keep/drop verdict (off-niche videos come down `false`);
  /// null until the feed is classified.
  final bool? isGood;

  /// "Combat Culture ‧ 168K views" (drops the views clause when hidden).
  String get metaLabel {
    final views = formatViewCount(viewCount);
    return views.isEmpty ? channelName : '$channelName ‧ $views views';
  }

  factory Video.fromJson(Map<String, dynamic> json) {
    return Video(
      url: (json['url'] as String?) ?? '',
      title: (json['title'] as String?) ?? '',
      thumbnailUrl: (json['thumbnail_url'] as String?) ?? '',
      channelName: (json['channel_name'] as String?) ?? '',
      channelUrl: (json['channel_url'] as String?) ?? '',
      channelAvatarUrl: (json['channel_avatar_url'] as String?) ?? '',
      viewCount: json['view_count'] as int?,
      // Missing → sort last (least relevant).
      relevanceIndex: (json['relevance_index'] as int?) ?? 1 << 30,
      isGood: json['is_good'] as bool?,
      // The API sends a single `tag` / `big_group` string; wrap each into a
      // one-element list so the list-based carousel grouping keeps working.
      tags: _wrap(json['tag']),
      bigGroups: _wrap(json['big_group']),
    );
  }

  /// A non-empty wire string → a one-element list; anything else → empty.
  static List<String> _wrap(dynamic raw) =>
      raw is String && raw.isNotEmpty ? [raw] : const [];
}
