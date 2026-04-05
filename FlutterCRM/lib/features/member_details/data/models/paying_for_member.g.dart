// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'paying_for_member.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PayingForMember _$PayingForMemberFromJson(
        Map<String, dynamic> json) =>
    PayingForMember(
      crmUserId: json['crm_user_id'] as String,
      firstName: json['first_name'] as String,
      lastName: json['last_name'] as String,
      photoUrl: json['photo_url'] as String?,
      status: MembershipStatus.fromJson(
        json['status'] as String,
      ),
      classCount: (json['class_count'] as num?)?.toInt(),
      classesUsed:
          (json['classes_used'] as num?)?.toInt() ?? 0,
      classesRemaining:
          (json['classes_remaining'] as num?)?.toInt(),
    );
