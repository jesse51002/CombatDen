// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'billing_reward_card.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

BillingRewardCard _$BillingRewardCardFromJson(Map<String, dynamic> json) =>
    BillingRewardCard(
      rewardId: json['reward_id'] as String,
      title: json['title'] as String,
      priceLabel: json['price_label'] as String,
      imageUrl: json['image_url'] as String,
      pointCost: (json['point_cost'] as num).toInt(),
    );
