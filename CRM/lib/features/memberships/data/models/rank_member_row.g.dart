// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'rank_member_row.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

RankMemberRow _$RankMemberRowFromJson(Map<String, dynamic> json) =>
    RankMemberRow(
      memberId: json['member_id'] as String,
      name: json['name'] as String,
      avatarUrl: json['avatar_url'] as String?,
      currentSubIndex: (json['current_sub_index'] as num?)?.toInt(),
      subLabel: json['sub_label'] as String?,
      classesSince: (json['classes_since'] as num).toInt(),
      stepDenominator: (json['step_denominator'] as num?)?.toInt(),
    );
