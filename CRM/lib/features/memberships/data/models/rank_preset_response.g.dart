// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'rank_preset_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

RankPresetResponse _$RankPresetResponseFromJson(Map<String, dynamic> json) =>
    RankPresetResponse(
      presetId: json['preset_id'] as String,
      presetKind: RankPresetKind.fromJson(json['preset_kind'] as String),
      mainRankNumOrder: (json['main_rank_num_order'] as num).toInt(),
      name: json['name'] as String,
      imageUrl: json['image_url'] as String?,
      classesToNextMajor: (json['classes_to_next_major'] as num).toInt(),
      subRankCount: (json['sub_rank_count'] as num?)?.toInt() ?? 0,
      impliedSubRankType: RankSubType.fromJsonNullable(
        json['implied_sub_rank_type'] as String?,
      ),
    );
