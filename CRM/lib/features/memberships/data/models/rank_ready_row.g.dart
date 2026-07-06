// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'rank_ready_row.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

RankReadyRow _$RankReadyRowFromJson(Map<String, dynamic> json) => RankReadyRow(
  memberId: json['member_id'] as String,
  name: json['name'] as String,
  avatarUrl: json['avatar_url'] as String?,
  mainRankId: json['main_rank_id'] as String,
  mainName: json['main_name'] as String,
  currentSubIndex: (json['current_sub_index'] as num?)?.toInt(),
  subLabel: json['sub_label'] as String?,
  imageUrl: json['image_url'] as String?,
  classesSince: (json['classes_since'] as num).toInt(),
  stepDenominator: (json['step_denominator'] as num?)?.toInt(),
);
