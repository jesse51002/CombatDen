// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'main_rank.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

MainRank _$MainRankFromJson(Map<String, dynamic> json) => MainRank(
  rankId: json['rank_id'] as String,
  gymId: json['gym_id'] as String,
  mainRankNumOrder: (json['main_rank_num_order'] as num).toInt(),
  name: json['name'] as String,
  imageUrl: json['image_url'] as String?,
  classesToNextMajor: (json['classes_to_next_major'] as num).toInt(),
  subRankCount: (json['sub_rank_count'] as num?)?.toInt() ?? 0,
  subRankImageOverrides:
      (json['sub_rank_image_overrides'] as Map<String, dynamic>?)?.map(
        (k, e) => MapEntry(k, e as String),
      ) ??
      {},
  createdAt: DateTime.parse(json['created_at'] as String),
);
