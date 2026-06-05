// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'waiver_signatory_row.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

WaiverSignatoryRow _$WaiverSignatoryRowFromJson(Map<String, dynamic> json) =>
    WaiverSignatoryRow(
      memberId: json['member_id'] as String,
      firstName: json['first_name'] as String,
      lastName: json['last_name'] as String,
      signed: json['signed'] as bool? ?? false,
      signedAt: json['signed_at'] == null
          ? null
          : DateTime.parse(json['signed_at'] as String),
      waiverVersionId: json['waiver_version_id'] as String?,
      versionNumber: (json['version_number'] as num?)?.toInt(),
      signedCurrentVersion: json['signed_current_version'] as bool? ?? false,
    );
