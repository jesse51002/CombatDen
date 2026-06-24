// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'discount_info.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

DiscountInfo _$DiscountInfoFromJson(Map<String, dynamic> json) => DiscountInfo(
  appliedDiscountId: json['applied_discount_id'] as String,
  itemId: json['item_id'] as String,
  memberId: json['member_id'] as String,
  gymId: json['gym_id'] as String,
  valueId: json['value_id'] as String,
  discountId: json['discount_id'] as String,
  discountType: DiscountType.fromJson(json['discount_type'] as String),
  discountName: json['discount_name'] as String,
  percentageOff: (json['percentage_off'] as num?)?.toDouble(),
  dollarOff: (json['dollar_off'] as num?)?.toInt(),
  endDate: json['end_date'] == null
      ? null
      : DateTime.parse(json['end_date'] as String),
);
