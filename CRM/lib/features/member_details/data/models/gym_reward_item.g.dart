// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'gym_reward_item.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

GymRewardItem _$GymRewardItemFromJson(Map<String, dynamic> json) =>
    GymRewardItem(
      rewardId: json['reward_id'] as String,
      title: json['title'] as String,
      pointCost: (json['point_cost'] as num).toInt(),
      priceLabel: json['price_label'] as String?,
      imageUrl: json['image_url'] as String?,
      isActive: json['is_active'] as bool,
    );
