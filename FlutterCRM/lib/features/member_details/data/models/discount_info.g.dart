// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'discount_info.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

DiscountInfo _$DiscountInfoFromJson(Map<String, dynamic> json) => DiscountInfo(
  discountId: json['discount_id'] as String,
  discountName: json['discount_name'] as String,
  percentageOff: (json['percentage_off'] as num?)?.toDouble(),
  dollarOff: (json['dollar_off'] as num?)?.toDouble(),
  startDate: json['start_date'] == null
      ? null
      : DateTime.parse(json['start_date'] as String),
  endDate: json['end_date'] == null
      ? null
      : DateTime.parse(json['end_date'] as String),
);
