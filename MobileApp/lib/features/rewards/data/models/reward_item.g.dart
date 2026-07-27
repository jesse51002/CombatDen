// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'reward_item.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

RewardItem _$RewardItemFromJson(Map<String, dynamic> json) => RewardItem(
  rewardId: json['reward_id'] as String,
  gymId: json['gym_id'] as String,
  title: json['title'] as String,
  pointCost: (json['point_cost'] as num).toInt(),
  imageUrl: json['image_url'] as String,
  priceLabel: json['price_label'] as String,
  isActive: json['is_active'] as bool,
  createdAt: json['created_at'] as String,
);
