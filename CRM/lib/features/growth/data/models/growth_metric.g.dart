// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'growth_metric.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

GrowthMetric _$GrowthMetricFromJson(Map<String, dynamic> json) => GrowthMetric(
  key: json['key'] as String,
  name: json['name'] as String,
  categories: GrowthCategory.listFromJson(json['categories'] as List),
  type: GrowthMetricType.fromJson(json['type'] as String),
  order: (json['order'] as num).toInt(),
  computedAt: DateTime.parse(json['computed_at'] as String),
  data: _dataFromJson(_readWholeMetric(json, 'data')),
);
