// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'card_on_file.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CardOnFile _$CardOnFileFromJson(Map<String, dynamic> json) => CardOnFile(
  brand: json['brand'] as String,
  lastFour: json['last_four'] as String,
  expMonth: (json['exp_month'] as num).toInt(),
  expYear: (json['exp_year'] as num).toInt(),
);
