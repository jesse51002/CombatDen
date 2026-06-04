// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'discount_info.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

DiscountInfo _$DiscountInfoFromJson(Map<String, dynamic> json) => DiscountInfo(
  discountId: json['discount_id'] as String,
  discountName: json['discount_name'] as String,
  discountType: json['discount_type'] as String,
  percentageOff: (json['percentage_off'] as num?)?.toDouble(),
  dollarOff: (json['dollar_off'] as num?)?.toInt(),
  endDate: json['end_date'] == null
      ? null
      : DateTime.parse(json['end_date'] as String),
);
