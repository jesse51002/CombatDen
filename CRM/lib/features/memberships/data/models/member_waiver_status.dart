import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'member_waiver_status.g.dart';

/// One waiver and a given member's latest sign status for it,
/// from `GET /api/v1/waivers/signatures/by-member/{member_id}`
/// — backs the member-detail Waivers section.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createToJson: false,
)
class MemberWaiverStatus extends Equatable {
  final String waiverId;
  final String name;
  final String? currentVersionId;
  final int? currentVersionNumber;
  @JsonKey(defaultValue: false)
  final bool signed;
  final String? signedVersionId;
  final int? signedVersionNumber;
  final DateTime? signedAt;
  @JsonKey(defaultValue: false)
  final bool signedCurrentVersion;

  const MemberWaiverStatus({
    required this.waiverId,
    required this.name,
    this.currentVersionId,
    this.currentVersionNumber,
    this.signed = false,
    this.signedVersionId,
    this.signedVersionNumber,
    this.signedAt,
    this.signedCurrentVersion = false,
  });

  factory MemberWaiverStatus.fromJson(
    Map<String, dynamic> json,
  ) =>
      _$MemberWaiverStatusFromJson(json);

  @override
  List<Object?> get props => [
        waiverId,
        name,
        currentVersionId,
        currentVersionNumber,
        signed,
        signedVersionId,
        signedVersionNumber,
        signedAt,
        signedCurrentVersion,
      ];
}
