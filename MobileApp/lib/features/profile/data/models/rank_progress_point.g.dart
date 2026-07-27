// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'rank_progress_point.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

RankProgressPoint _$RankProgressPointFromJson(Map<String, dynamic> json) =>
    RankProgressPoint(
      date: json['date'] as String,
      classesIntoRank: (json['classes_into_rank'] as num).toInt(),
      classesNeeded: (json['classes_needed'] as num).toInt(),
    );
