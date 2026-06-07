// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'member_waiver_status.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

MemberWaiverStatus _$MemberWaiverStatusFromJson(Map<String, dynamic> json) =>
    MemberWaiverStatus(
      waiverId: json['waiver_id'] as String,
      name: json['name'] as String,
      currentVersionId: json['current_version_id'] as String?,
      currentVersionNumber: (json['current_version_number'] as num?)?.toInt(),
      signed: json['signed'] as bool? ?? false,
      signedVersionId: json['signed_version_id'] as String?,
      signedVersionNumber: (json['signed_version_number'] as num?)?.toInt(),
      signedAt: json['signed_at'] == null
          ? null
          : DateTime.parse(json['signed_at'] as String),
      signedCurrentVersion: json['signed_current_version'] as bool? ?? false,
    );
