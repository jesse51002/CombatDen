// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'rank_summary.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

RankSummary _$RankSummaryFromJson(Map<String, dynamic> json) => RankSummary(
  rankId: json['rank_id'] as String,
  mainName: json['main_name'] as String,
  subName: json['sub_name'] as String,
  color: json['color'] as String?,
  imageUrl: json['image_url'] as String?,
  mainRankNumOrder: (json['main_rank_num_order'] as num).toInt(),
  subRankNumOrder: (json['sub_rank_num_order'] as num).toInt(),
);
