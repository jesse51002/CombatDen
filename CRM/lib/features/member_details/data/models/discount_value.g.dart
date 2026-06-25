// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'discount_value.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

DiscountValue _$DiscountValueFromJson(Map<String, dynamic> json) =>
    DiscountValue(
      percentageOff: (json['percentage_off'] as num?)?.toDouble(),
      dollarOff: (json['dollar_off'] as num?)?.toInt(),
      durationAmount: (json['duration_amount'] as num?)?.toInt(),
      durationUnit: DiscountValue._durationUnitOrNull(json['duration_unit']),
      endDate: json['end_date'] == null
          ? null
          : DateTime.parse(json['end_date'] as String),
    );

Map<String, dynamic> _$DiscountValueToJson(DiscountValue instance) =>
    <String, dynamic>{
      'percentage_off': ?instance.percentageOff,
      'dollar_off': ?instance.dollarOff,
      'duration_amount': ?instance.durationAmount,
      'duration_unit': ?instance.durationUnit,
      'end_date': ?DiscountValue._dateToJson(instance.endDate),
    };
