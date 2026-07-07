// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'rank.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Rank _$RankFromJson(Map<String, dynamic> json) => Rank(
  rankId: json['rank_id'] as String,
  name: json['name'] as String,
  subIndex: (json['sub_index'] as num?)?.toInt(),
  subLabel: json['sub_label'] as String?,
  imageUrl: json['image_url'] as String?,
  classesToNextMajor: (json['classes_to_next_major'] as num).toInt(),
  classesTillNextStep: (json['classes_till_next_step'] as num).toInt(),
  classesSinceRank: (json['classes_since_rank'] as num?)?.toInt() ?? 0,
);
