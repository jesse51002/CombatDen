// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'rank_sub_rank_counts.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

RankSubRankCounts _$RankSubRankCountsFromJson(Map<String, dynamic> json) =>
    RankSubRankCounts(
      totalCount: (json['total_count'] as num).toInt(),
      counts:
          (json['counts'] as List<dynamic>?)
              ?.map((e) => RankSubRankCount.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );

RankSubRankCount _$RankSubRankCountFromJson(Map<String, dynamic> json) =>
    RankSubRankCount(
      subIndex: (json['sub_index'] as num?)?.toInt(),
      count: (json['count'] as num).toInt(),
    );
