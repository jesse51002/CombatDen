// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'linked_discount_value.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

LinkedDiscountValue _$LinkedDiscountValueFromJson(Map<String, dynamic> json) =>
    LinkedDiscountValue(
      percentageOff: (json['percentage_off'] as num?)?.toDouble(),
      dollarOff: (json['dollar_off'] as num?)?.toInt(),
    );

Map<String, dynamic> _$LinkedDiscountValueToJson(
  LinkedDiscountValue instance,
) => <String, dynamic>{
  'percentage_off': ?instance.percentageOff,
  'dollar_off': ?instance.dollarOff,
};
