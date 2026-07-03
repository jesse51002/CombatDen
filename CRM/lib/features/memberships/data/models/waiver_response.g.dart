// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'waiver_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

WaiverResponse _$WaiverResponseFromJson(Map<String, dynamic> json) =>
    WaiverResponse(
      waiverId: json['waiver_id'] as String,
      gymId: json['gym_id'] as String,
      name: json['name'] as String,
      waiverType: WaiverType.fromJson(json['waiver_type'] as String),
      currentVersionId: json['current_version_id'] as String?,
      currentVersionNumber: (json['current_version_number'] as num?)?.toInt(),
      currentVersionSignedCount:
          (json['current_version_signed_count'] as num?)?.toInt() ?? 0,
      isDeleted: json['is_deleted'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      currentVersion: json['current_version'] == null
          ? null
          : WaiverVersionResponse.fromJson(
              json['current_version'] as Map<String, dynamic>,
            ),
    );
