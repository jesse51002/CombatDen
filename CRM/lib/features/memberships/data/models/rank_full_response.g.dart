// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'rank_full_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

RankFullResponse _$RankFullResponseFromJson(Map<String, dynamic> json) =>
    RankFullResponse(
      rankId: json['rank_id'] as String,
      gymId: json['gym_id'] as String,
      mainName: json['main_name'] as String,
      subName: json['sub_name'] as String,
      color: json['color'] as String?,
      imageUrl: json['image_url'] as String?,
      mainRankNumOrder: (json['main_rank_num_order'] as num).toInt(),
      subRankNumOrder: (json['sub_rank_num_order'] as num).toInt(),
      classesTillRankup: (json['classes_till_rankup'] as num).toInt(),
    );
