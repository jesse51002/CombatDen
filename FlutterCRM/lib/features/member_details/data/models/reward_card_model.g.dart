// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'reward_card_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

RewardCardModel _$RewardCardModelFromJson(Map<String, dynamic> json) =>
    RewardCardModel(
      rewardId: json['reward_id'] as String,
      title: json['title'] as String,
      pointCost: (json['point_cost'] as num).toInt(),
      amountOff: json['amount_off'] as String?,
      imageUrl: json['image_url'] as String?,
    );
