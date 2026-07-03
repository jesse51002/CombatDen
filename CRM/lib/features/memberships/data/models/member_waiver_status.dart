import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

import 'package:crm/features/memberships/data/models/waiver_type.dart';

part 'member_waiver_status.g.dart';

/// One waiver and a given member's latest sign status for it,
/// from `GET /api/v1/waivers/signatures/by-member/{member_id}`
/// — backs the member-detail Waivers section.
///
/// The rows are the UNION of (waivers required by the member's
/// current memberships' plans) and (waivers the member has ever
/// signed), so a signature stays visible after the waiver stops
/// being required or is archived (the signature is the legal
/// record). [meetsFloor] is the compliance verdict — the latest
/// signature sits at or above the waiver's re-sign floor; a
/// `signed && !meetsFloor` row therefore needs re-signing.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createToJson: false,
)
class MemberWaiverStatus extends Equatable {
  final String waiverId;
  final String name;
  @JsonKey(fromJson: WaiverType.fromJson)
  final WaiverType waiverType;
  @JsonKey(defaultValue: false)
  final bool isDeleted;
  @JsonKey(defaultValue: false)
  final bool required;
  final String? currentVersionId;
  final int? currentVersionNumber;
  @JsonKey(defaultValue: false)
  final bool signed;
  final String? signedVersionId;
  final int? signedVersionNumber;
  final DateTime? signedAt;
  @JsonKey(defaultValue: false)
  final bool signedCurrentVersion;
  @JsonKey(defaultValue: false)
  final bool meetsFloor;

  const MemberWaiverStatus({
    required this.waiverId,
    required this.name,
    required this.waiverType,
    this.isDeleted = false,
    this.required = false,
    this.currentVersionId,
    this.currentVersionNumber,
    this.signed = false,
    this.signedVersionId,
    this.signedVersionNumber,
    this.signedAt,
    this.signedCurrentVersion = false,
    this.meetsFloor = false,
  });

  factory MemberWaiverStatus.fromJson(
    Map<String, dynamic> json,
  ) =>
      _$MemberWaiverStatusFromJson(json);

  @override
  List<Object?> get props => [
        waiverId,
        name,
        waiverType,
        isDeleted,
        required,
        currentVersionId,
        currentVersionNumber,
        signed,
        signedVersionId,
        signedVersionNumber,
        signedAt,
        signedCurrentVersion,
        meetsFloor,
      ];
}
