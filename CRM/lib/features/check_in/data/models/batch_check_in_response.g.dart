// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'batch_check_in_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

BatchCheckInResponse _$BatchCheckInResponseFromJson(
  Map<String, dynamic> json,
) => BatchCheckInResponse(
  classId: json['class_id'] as String,
  occurrenceDate: json['occurrence_date'] as String,
  results:
      (json['results'] as List<dynamic>?)
          ?.map(
            (e) => BatchCheckInResultItem.fromJson(e as Map<String, dynamic>),
          )
          .toList() ??
      [],
);
