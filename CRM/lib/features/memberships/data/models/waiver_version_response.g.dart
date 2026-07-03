// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'waiver_version_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

WaiverVersionResponse _$WaiverVersionResponseFromJson(
  Map<String, dynamic> json,
) => WaiverVersionResponse(
  versionId: json['version_id'] as String,
  waiverId: json['waiver_id'] as String,
  gymId: json['gym_id'] as String,
  versionNumber: (json['version_number'] as num).toInt(),
  body: json['body'] as String,
  contentHash: json['content_hash'] as String,
  createdAt: DateTime.parse(json['created_at'] as String),
  signatureCount: (json['signature_count'] as num?)?.toInt() ?? 0,
  requiresResign: json['requires_resign'] as bool? ?? true,
);
