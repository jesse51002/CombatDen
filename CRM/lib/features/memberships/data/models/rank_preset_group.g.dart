// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'rank_preset_group.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

RankSubPreset _$RankSubPresetFromJson(Map<String, dynamic> json) =>
    RankSubPreset(
      presetId: json['preset_id'] as String,
      subRankNumOrder: (json['sub_rank_num_order'] as num).toInt(),
      subName: json['sub_name'] as String,
      classesTillRankup: (json['classes_till_rankup'] as num).toInt(),
      imageUrl: json['image_url'] as String?,
      color: json['color'] as String?,
    );

RankPresetGroup _$RankPresetGroupFromJson(Map<String, dynamic> json) =>
    RankPresetGroup(
      mainRankNumOrder: (json['main_rank_num_order'] as num).toInt(),
      mainName: json['main_name'] as String,
      subRanks: (json['sub_ranks'] as List<dynamic>)
          .map((e) => RankSubPreset.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
