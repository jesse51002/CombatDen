// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'attendee_list_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Attendee _$AttendeeFromJson(Map<String, dynamic> json) => Attendee(
  memberId: json['member_id'] as String,
  fullName: json['full_name'] as String,
  signedUp: json['signed_up'] as bool,
  attended: json['attended'] as bool,
  logId: json['log_id'] as String?,
  planId: json['plan_id'] as String?,
  itemId: json['item_id'] as String?,
);

AttendeeListResponse _$AttendeeListResponseFromJson(
  Map<String, dynamic> json,
) => AttendeeListResponse(
  classId: json['class_id'] as String,
  occurrenceDate: json['occurrence_date'] as String,
  classHistoryId: json['class_history_id'] as String?,
  attendees:
      (json['attendees'] as List<dynamic>?)
          ?.map((e) => Attendee.fromJson(e as Map<String, dynamic>))
          .toList() ??
      [],
);
