// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'discount_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

DiscountResponse _$DiscountResponseFromJson(Map<String, dynamic> json) =>
    DiscountResponse(
      discountId: json['discount_id'] as String,
      gymId: json['gym_id'] as String,
      discountName: json['discount_name'] as String,
      discountType: DiscountType.fromJson(json['discount_type'] as String),
      percentageOff: (json['percentage_off'] as num?)?.toDouble(),
      dollarOff: (json['dollar_off'] as num?)?.toInt(),
      membershipPlanId: json['membership_plan_id'] as String?,
      linkedDiscountNum: (json['linked_discount_num'] as num?)?.toInt(),
      duration: StripeCouponDuration.fromJson(json['duration'] as String),
      durationInMonths: (json['duration_in_months'] as num?)?.toInt(),
      stripeCouponId: json['stripe_coupon_id'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
