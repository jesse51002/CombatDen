// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'member_rank_progress.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

MemberRankProgress _$MemberRankProgressFromJson(Map<String, dynamic> json) =>
    MemberRankProgress(
      points:
          (json['points'] as List<dynamic>?)
              ?.map(
                (e) => RankProgressPoint.fromJson(e as Map<String, dynamic>),
              )
              .toList() ??
          [],
    );
