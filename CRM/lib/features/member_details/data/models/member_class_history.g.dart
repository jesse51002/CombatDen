// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'member_class_history.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

MemberClassHistoryRow _$MemberClassHistoryRowFromJson(
  Map<String, dynamic> json,
) => MemberClassHistoryRow(
  classId: json['class_id'] as String,
  className: json['class_name'] as String,
  imageUrl: json['image_url'] as String?,
  originalDate: DateTime.parse(json['original_date'] as String),
  originalTime: json['original_time'] as String,
  occurredAt: json['occurred_at'] == null
      ? null
      : DateTime.parse(json['occurred_at'] as String),
  status: MemberClassHistoryStatus.fromJson(json['status'] as String),
);

MemberClassHistoryResponse _$MemberClassHistoryResponseFromJson(
  Map<String, dynamic> json,
) => MemberClassHistoryResponse(
  upcoming:
      (json['upcoming'] as List<dynamic>?)
          ?.map(
            (e) => MemberClassHistoryRow.fromJson(e as Map<String, dynamic>),
          )
          .toList() ??
      [],
  history:
      (json['history'] as List<dynamic>?)
          ?.map(
            (e) => MemberClassHistoryRow.fromJson(e as Map<String, dynamic>),
          )
          .toList() ??
      [],
  hasMore: json['has_more'] as bool,
);
