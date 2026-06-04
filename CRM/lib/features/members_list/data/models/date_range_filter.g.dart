// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'date_range_filter.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

DateRangeFilter _$DateRangeFilterFromJson(Map<String, dynamic> json) =>
    DateRangeFilter(
      startDate: json['start_date'] as String?,
      endDate: json['end_date'] as String?,
    );

Map<String, dynamic> _$DateRangeFilterToJson(DateRangeFilter instance) =>
    <String, dynamic>{
      'start_date': instance.startDate,
      'end_date': instance.endDate,
    };
