import 'package:app_management/features/members/presentation/widgets/member_app/videos_tab/video_format_helpers.dart';

/// One video as served by the VideoService
/// (`GET /themes/{designId}/videos` -> `VideoCard`). Field names mirror the
/// API so the JSON parse stays mechanical. See
/// `../../../../VideoService/schema/video_feed.py`.
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

  /// Backend relevancy rank: 0 = top hit, lower is more relevant.
  final int relevanceIndex;

  /// Fine-grained genre tags (lowercase wire strings); drive carousels.
  final List<String> tags;

  /// Coarse grouping the server derived from [tags] (`educational` /
  /// `entertainment`); the feed's top-level grouping.
  final List<String> bigGroups;

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
      relevanceIndex: (json['relevance_index'] as int?) ?? 1 << 30,
      tags: _parseStrings(json['tags']),
      bigGroups: _parseStrings(json['big_groups']),
    );
  }

  static List<String> _parseStrings(dynamic raw) {
    if (raw is! List) return const [];
    return raw.whereType<String>().toList(growable: false);
  }
}
