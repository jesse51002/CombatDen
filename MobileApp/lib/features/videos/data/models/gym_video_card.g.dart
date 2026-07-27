// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'gym_video_card.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

GymVideoCard _$GymVideoCardFromJson(Map<String, dynamic> json) => GymVideoCard(
  videoId: json['video_id'] as String,
  url: json['url'] as String,
  title: json['title'] as String,
  thumbnailUrl: json['thumbnail_url'] as String,
  channelName: json['channel_name'] as String,
  channelUrl: json['channel_url'] as String,
  channelAvatarUrl: json['channel_avatar_url'] as String,
  relevanceIndex: (json['relevance_index'] as num).toInt(),
  viewCount: (json['view_count'] as num?)?.toInt(),
  durationSeconds: (json['duration_seconds'] as num?)?.toInt(),
  tag: videoGenreOrNullFromJson(json['tag']),
  ownerAdded: json['owner_added'] as bool? ?? false,
  enriched: json['enriched'] as bool? ?? true,
  bigGroup: bigGroupOrNullFromJson(json['big_group']),
);
