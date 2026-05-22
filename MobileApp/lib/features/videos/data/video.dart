import 'package:mobile_app/features/videos/data/video_helpers.dart';

/// A single video as served by the VideoService
/// (`GET /apps/{appId}/videos` → `VideoCard`). Field names mirror the
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

  /// Fine-grained genre tags; drive the per-tag carousels.
  final List<VideoTag> tags;

  /// Coarse educational/entertainment sort (server-derived from [tags]);
  /// the home page's top-level grouping. Can contain both.
  final List<BigGroup> bigGroups;

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
      tags: _parseTags(json['tags']),
      bigGroups: _parseBigGroups(json['big_groups']),
    );
  }

  static List<VideoTag> _parseTags(dynamic raw) {
    if (raw is! List) return const [VideoTag.unknown];
    return raw.whereType<String>().map(VideoTag.fromWire).toList(
      growable: false,
    );
  }

  static List<BigGroup> _parseBigGroups(dynamic raw) {
    if (raw is! List) return const [];
    return raw.whereType<String>().map(BigGroup.fromWire).toList(
      growable: false,
    );
  }
}

/// The 12 content genres (mirrors `../VideoService/schema/video_type.py`),
/// plus an [unknown] fallback so a new server-side genre never crashes the
/// parse.
enum VideoTag {
  educational,
  tutorial,
  informative,
  news,
  review,
  interview,
  entertainment,
  vlog,
  behindTheScenes,
  professional,
  clips,
  fun,
  unknown;

  /// The lowercase wire value the API serializes.
  String get wire => switch (this) {
    VideoTag.behindTheScenes => 'behind_the_scenes',
    _ => name,
  };

  static VideoTag fromWire(String raw) => VideoTag.values.firstWhere(
    (t) => t.wire == raw,
    orElse: () => VideoTag.unknown,
  );
}

/// The coarse two-way sort (mirrors `../VideoService/schema/big_group.py`),
/// plus an [unknown] fallback.
enum BigGroup {
  educational,
  entertainment,
  unknown;

  static BigGroup fromWire(String raw) => BigGroup.values.firstWhere(
    (g) => g.name == raw,
    orElse: () => BigGroup.unknown,
  );
}
