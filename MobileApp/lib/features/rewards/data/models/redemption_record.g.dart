// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'redemption_record.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

RedemptionRecord _$RedemptionRecordFromJson(Map<String, dynamic> json) =>
    RedemptionRecord(
      redemptionId: json['redemption_id'] as String,
      rewardId: json['reward_id'] as String,
      title: json['title'] as String,
      imageUrl: json['image_url'] as String,
      priceLabel: json['price_label'] as String,
      pointCost: (json['point_cost'] as num).toInt(),
      requestedAt: json['requested_at'] as String,
      status: redemptionStatusFromJson(json['status']),
    );
