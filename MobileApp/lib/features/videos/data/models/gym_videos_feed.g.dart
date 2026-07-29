// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'gym_videos_feed.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

GymVideosFeed _$GymVideosFeedFromJson(Map<String, dynamic> json) =>
    GymVideosFeed(
      total: (json['total'] as num).toInt(),
      limit: (json['limit'] as num).toInt(),
      offset: (json['offset'] as num).toInt(),
      videos:
          (json['videos'] as List<dynamic>?)
              ?.map((e) => GymVideoCard.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );
