// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'rank_member_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

RankMemberResponse _$RankMemberResponseFromJson(Map<String, dynamic> json) =>
    RankMemberResponse(
      memberId: json['member_id'] as String,
      newRank: json['new_rank'] == null
          ? null
          : MainRank.fromJson(json['new_rank'] as Map<String, dynamic>),
      newSubIndex: (json['new_sub_index'] as num?)?.toInt(),
      newSubLabel: json['new_sub_label'] as String?,
      newDisplayName: json['new_display_name'] as String?,
    );
