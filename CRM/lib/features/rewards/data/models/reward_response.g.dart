// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'reward_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

RewardResponse _$RewardResponseFromJson(Map<String, dynamic> json) =>
    RewardResponse(
      rewardId: json['rewardId'] as String,
      gymId: json['gymId'] as String,
      title: json['title'] as String,
      pointCost: (json['pointCost'] as num).toInt(),
      amountOff: json['amountOff'] as String?,
      imageUrl: json['imageUrl'] as String?,
      priceLabel: json['priceLabel'] as String?,
      isActive: json['isActive'] as bool,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );

Map<String, dynamic> _$RewardResponseToJson(RewardResponse instance) =>
    <String, dynamic>{
      'rewardId': instance.rewardId,
      'gymId': instance.gymId,
      'title': instance.title,
      'pointCost': instance.pointCost,
      'amountOff': instance.amountOff,
      'imageUrl': instance.imageUrl,
      'priceLabel': instance.priceLabel,
      'isActive': instance.isActive,
      'createdAt': instance.createdAt.toIso8601String(),
    };
