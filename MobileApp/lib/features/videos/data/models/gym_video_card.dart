import 'package:json_annotation/json_annotation.dart';

import 'package:mobile_app/features/videos/data/gym_video_helpers.dart';
import 'package:mobile_app/features/videos/data/models/big_group.dart';
import 'package:mobile_app/features/videos/data/models/video_genre.dart';

part 'gym_video_card.g.dart';

/// One video, exactly the fields the app renders — a card in a gym's served
/// feed.
///
/// Mirrors `GymVideoCard` in
/// `FastApiBackend/src/videos/schema/videos_schema.py`
/// (`GET /api/v1/member/gyms/{gid}/members/{mid}/videos`). [videoId] is the
/// shared-pool YouTube id (required — the client posts it back on a rec click).
/// [tag] is the single genre (nullable until the pool is tagged; resilient
/// parse). [bigGroup] is the server-computed coarse sort (derived from [tag]).
/// [ownerAdded] / [enriched] are always present on the served feed; kept for
/// schema fidelity even though the member surface doesn't render them.
@JsonSerializable(fieldRename: FieldRename.snake, createToJson: false)
class GymVideoCard {
  final String videoId;
  final String url;
  final String title;
  final String thumbnailUrl;
  final String channelName;
  final String channelUrl;
  final String channelAvatarUrl;

  /// The "views" label; null when the channel hides its stats.
  final int? viewCount;

  /// Runtime in seconds; null when unknown.
  final int? durationSeconds;

  /// Backend relevancy rank: 0 = top hit. A secondary sort key only — the feed
  /// arrives already ranked (personalized) server-side, so the app preserves
  /// the wire order rather than re-sorting on this.
  final int relevanceIndex;

  /// The video's single genre tag; null until the pool is tagged. Carousels
  /// group on it.
  @JsonKey(fromJson: videoGenreOrNullFromJson)
  final VideoGenre? tag;

  /// True when this is an owner-added "Your videos" row.
  @JsonKey(defaultValue: false)
  final bool ownerAdded;

  /// Whether the video has a RAG embedding yet (the served feed is always
  /// enriched, so this is true here).
  @JsonKey(defaultValue: true)
  final bool enriched;

  /// The server-computed coarse educational/entertainment grouping; null until
  /// classified.
  @JsonKey(fromJson: bigGroupOrNullFromJson)
  final BigGroup? bigGroup;

  const GymVideoCard({
    required this.videoId,
    required this.url,
    required this.title,
    required this.thumbnailUrl,
    required this.channelName,
    required this.channelUrl,
    required this.channelAvatarUrl,
    required this.relevanceIndex,
    this.viewCount,
    this.durationSeconds,
    this.tag,
    this.ownerAdded = false,
    this.enriched = true,
    this.bigGroup,
  });

  /// "Combat Culture ‧ 168K views" (drops the views clause when hidden).
  String get metaLabel {
    final views = formatViewCount(viewCount);
    return views.isEmpty ? channelName : '$channelName ‧ $views views';
  }

  factory GymVideoCard.fromJson(Map<String, dynamic> json) =>
      _$GymVideoCardFromJson(json);
}
