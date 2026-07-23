// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'member_membership_applied_discount.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

MemberMembershipAppliedDiscount _$MemberMembershipAppliedDiscountFromJson(
  Map<String, dynamic> json,
) => MemberMembershipAppliedDiscount(
  appliedDiscountId: json['applied_discount_id'] as String,
  itemId: json['item_id'] as String,
  memberId: json['member_id'] as String,
  gymId: json['gym_id'] as String,
  valueId: json['value_id'] as String,
  discountId: json['discount_id'] as String,
  discountName: json['discount_name'] as String,
  discountType: $enumDecode(
    _$DiscountTypeEnumMap,
    json['discount_type'],
    unknownValue: DiscountType.unknown,
  ),
  percentageOff: (json['percentage_off'] as num?)?.toDouble(),
  dollarOff: (json['dollar_off'] as num?)?.toInt(),
  endDate: json['end_date'] as String?,
  stripeCouponId: json['stripe_coupon_id'] as String?,
);

const _$DiscountTypeEnumMap = {
  DiscountType.preset: 'preset',
  DiscountType.custom: 'custom',
  DiscountType.unknown: 'unknown',
};
