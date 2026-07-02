// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'rank.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Rank _$RankFromJson(Map<String, dynamic> json) => Rank(
  rankId: json['rank_id'] as String,
  mainName: json['main_name'] as String,
  subName: json['sub_name'] as String,
  imageUrl: json['image_url'] as String?,
  color: json['color'] as String?,
  classesTillRankup: (json['classes_till_rankup'] as num).toInt(),
  classesSinceRank: (json['classes_since_rank'] as num?)?.toInt() ?? 0,
);
