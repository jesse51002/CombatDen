// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'class_history.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

MemberClassHistoryRow _$MemberClassHistoryRowFromJson(
  Map<String, dynamic> json,
) => MemberClassHistoryRow(
  classId: json['class_id'] as String,
  className: json['class_name'] as String,
  imageUrl: json['image_url'] as String,
  originalDate: json['original_date'] as String,
  originalTime: json['original_time'] as String,
  durationMinutes: (json['duration_minutes'] as num).toInt(),
  status: $enumDecode(
    _$MemberClassHistoryStatusEnumMap,
    json['status'],
    unknownValue: MemberClassHistoryStatus.unknown,
  ),
  pointsWorth: (json['points_worth'] as num?)?.toInt() ?? 0,
  occurredAt: json['occurred_at'] as String?,
);

const _$MemberClassHistoryStatusEnumMap = {
  MemberClassHistoryStatus.reserved: 'reserved',
  MemberClassHistoryStatus.attended: 'attended',
  MemberClassHistoryStatus.noShow: 'no_show',
  MemberClassHistoryStatus.unknown: 'unknown',
};

MemberClassHistory _$MemberClassHistoryFromJson(Map<String, dynamic> json) =>
    MemberClassHistory(
      upcoming: (json['upcoming'] as List<dynamic>)
          .map((e) => MemberClassHistoryRow.fromJson(e as Map<String, dynamic>))
          .toList(),
      history: (json['history'] as List<dynamic>)
          .map((e) => MemberClassHistoryRow.fromJson(e as Map<String, dynamic>))
          .toList(),
      hasMore: json['has_more'] as bool,
    );
