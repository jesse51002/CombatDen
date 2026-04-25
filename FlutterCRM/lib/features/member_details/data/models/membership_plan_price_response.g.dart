// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'membership_plan_price_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

MembershipPlanPriceResponse _$MembershipPlanPriceResponseFromJson(
  Map<String, dynamic> json,
) => MembershipPlanPriceResponse(
  priceId: json['price_id'] as String,
  planId: json['plan_id'] as String,
  gymId: json['gym_id'] as String,
  stripePriceId: json['stripe_price_id'] as String,
  price: (json['price'] as num).toInt(),
  isActive: json['is_active'] as bool,
  createdAt: DateTime.parse(json['created_at'] as String),
);
