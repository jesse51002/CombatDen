// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'reward_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

RewardResponse _$RewardResponseFromJson(Map<String, dynamic> json) =>
    RewardResponse(
      rewardId: json['reward_id'] as String,
      gymId: json['gym_id'] as String,
      title: json['title'] as String,
      pointCost: (json['point_cost'] as num).toInt(),
      amountOff: json['amount_off'] as String?,
      imageUrl: json['image_url'] as String?,
      priceLabel: json['price_label'] as String?,
      isActive: json['is_active'] as bool,
      createdAt: DateTime.parse(json['created_at'] as String),
    );

Map<String, dynamic> _$RewardResponseToJson(RewardResponse instance) =>
    <String, dynamic>{
      'reward_id': instance.rewardId,
      'gym_id': instance.gymId,
      'title': instance.title,
      'point_cost': instance.pointCost,
      'amount_off': instance.amountOff,
      'image_url': instance.imageUrl,
      'price_label': instance.priceLabel,
      'is_active': instance.isActive,
      'created_at': instance.createdAt.toIso8601String(),
    };
