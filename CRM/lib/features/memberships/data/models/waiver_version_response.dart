import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'waiver_version_response.g.dart';

/// An immutable published version of a waiver's text, from
/// `GET /api/v1/waivers/{waiver_id}/versions` (and embedded
/// in a single-waiver get). [signatureCount] is how many
/// members signed this exact version.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createToJson: false,
)
class WaiverVersionResponse extends Equatable {
  final String versionId;
  final String waiverId;
  final String gymId;
  final int versionNumber;
  final String body;
  final String contentHash;
  final DateTime createdAt;
  @JsonKey(defaultValue: 0)
  final int signatureCount;

  /// Whether this version (as the highest such version) re-blocks prior
  /// signers — the re-sign floor. Correctable on the current version.
  @JsonKey(defaultValue: true)
  final bool requiresResign;

  const WaiverVersionResponse({
    required this.versionId,
    required this.waiverId,
    required this.gymId,
    required this.versionNumber,
    required this.body,
    required this.contentHash,
    required this.createdAt,
    this.signatureCount = 0,
    this.requiresResign = true,
  });

  factory WaiverVersionResponse.fromJson(
    Map<String, dynamic> json,
  ) =>
      _$WaiverVersionResponseFromJson(json);

  @override
  List<Object?> get props => [
        versionId,
        waiverId,
        gymId,
        versionNumber,
        body,
        contentHash,
        createdAt,
        signatureCount,
        requiresResign,
      ];
}
