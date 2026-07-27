// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'billing_rank.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

BillingRank _$BillingRankFromJson(Map<String, dynamic> json) => BillingRank(
  rankId: json['rank_id'] as String,
  name: json['name'] as String,
  classesToNextMajor: (json['classes_to_next_major'] as num).toInt(),
  classesTillNextStep: (json['classes_till_next_step'] as num).toInt(),
  subIndex: (json['sub_index'] as num?)?.toInt(),
  subLabel: json['sub_label'] as String?,
  imageUrl: json['image_url'] as String?,
  classesSinceRank: (json['classes_since_rank'] as num?)?.toInt() ?? 0,
  nextRankImageUrl: json['next_rank_image_url'] as String?,
);
