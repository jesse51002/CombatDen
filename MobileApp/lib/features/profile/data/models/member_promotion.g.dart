// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'member_promotion.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

MemberPromotion _$MemberPromotionFromJson(Map<String, dynamic> json) =>
    MemberPromotion(
      activityId: json['activity_id'] as String,
      promotedAt: DateTime.parse(json['promoted_at'] as String),
      oldRankName: json['old_rank_name'] as String?,
      newRankName: json['new_rank_name'] as String?,
      oldImageUrl: json['old_image_url'] as String?,
      newImageUrl: json['new_image_url'] as String?,
    );
