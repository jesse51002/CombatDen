import 'package:crm/features/members/data/youtube_url.dart';
import 'package:crm/features/members/presentation/widgets/member_app/videos_tab/video_format_helpers.dart';

/// One video as served by the VideoService
/// (`GET /gyms/{gymId}/videos` -> `VideoCard`). Field names mirror the
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
    this.durationSeconds,
    this.ownerAdded = false,
    this.enriched = true,
    String? videoId,
  }) : _videoId = videoId;

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

  /// Video length in seconds (`duration_seconds`); null when omitted.
  final int? durationSeconds;

  /// The shared-pool video id (`video_id`), when the source endpoint sends
  /// it. Prefer this over parsing [url] — see [videoId].
  final String? _videoId;

  /// True when this is an owner-added "Your videos" row rather than a
  /// scan-run video. Set by the merged serve feed (`GET .../videos`) and the
  /// owner listing (`GET .../videos/owner`); other read paths default to
  /// false.
  final bool ownerAdded;

  /// Whether the video has a RAG embedding yet. Always true except on the
  /// ungated owner listing (`GET .../videos/owner`), which can show a
  /// just-added video before it's enriched.
  final bool enriched;

  /// "Combat Culture ‧ 168K views" (drops the views clause when hidden).
  String get metaLabel {
    final views = formatViewCount(viewCount);
    return views.isEmpty ? channelName : '$channelName ‧ $views views';
  }

  /// The YouTube video id: the backend's explicit `video_id` when present,
  /// else recovered from [url] (the feed serves the canonical
  /// `watch?v=<id>` form). Empty when neither is available. Used as the
  /// path id for the remove call.
  String get videoId =>
      (_videoId != null && _videoId.isNotEmpty)
          ? _videoId
          : extractYoutubeId(url) ?? '';

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
      // The API sends a single `tag` / `big_group` string; wrap each into a
      // one-element list so the list-based grouping keeps working (mirrors
      // MobileApp's `Video.fromJson`).
      tags: _wrap(json['tag']),
      bigGroups: _wrap(json['big_group']),
      durationSeconds: (json['duration_seconds'] as num?)?.toInt(),
      videoId: json['video_id'] as String?,
      ownerAdded: (json['owner_added'] as bool?) ?? false,
      enriched: (json['enriched'] as bool?) ?? true,
    );
  }

  static List<String> _wrap(dynamic raw) =>
      (raw is String && raw.isNotEmpty) ? [raw] : const [];
}

/// One page of a gym's video feed: the videos plus the pre-pagination [total]
/// for that filter, so a "View all" grid knows whether more pages remain.
class VideoPage {
  final List<Video> videos;
  final int total;

  const VideoPage({required this.videos, required this.total});
}

/// One genre's preview row from `GET /gyms/{gymId}/videos/preview` — a [tag]
/// and its first few videos, sampled server-side (each genre individually) so
/// the whole "All" preview arrives in one request and no genre is starved.
class FeedSection {
  final String tag;
  final List<Video> videos;

  const FeedSection({required this.tag, required this.videos});

  factory FeedSection.fromJson(Map<String, dynamic> json) => FeedSection(
    tag: (json['tag'] as String?) ?? '',
    videos:
        (json['videos'] as List?)
            ?.whereType<Map>()
            .map((e) => Video.fromJson(Map<String, dynamic>.from(e)))
            .toList(growable: false) ??
        const [],
  );
}
