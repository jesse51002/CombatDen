// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'rank_retention.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

RankRetention _$RankRetentionFromJson(Map<String, dynamic> json) =>
    RankRetention(
      currentRank: (json['current_rank'] as num?)?.toInt(),
      rankName: json['rank_name'] as String?,
      rankImageUrl: json['rank_image_url'] as String?,
      classesInRank: (json['classes_in_rank'] as num).toInt(),
      estimatedClassesForRank: (json['estimated_classes_for_rank'] as num)
          .toInt(),
      recommendPromoIn: (json['recommend_promo_in'] as num?)?.toInt(),
      lastClass: json['last_class'] == null
          ? null
          : DateTime.parse(json['last_class'] as String),
      classStreakWeeks: (json['class_streak_weeks'] as num).toInt(),
      pointsBalance: (json['points_balance'] as num).toInt(),
      videosWatched: (json['videos_watched'] as num).toInt(),
    );
