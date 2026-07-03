import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

import 'package:crm/features/memberships/data/models/waiver_type.dart';
import 'package:crm/features/memberships/data/models/waiver_version_response.dart';

part 'waiver_response.g.dart';

/// A waiver catalog entry, from `GET /api/v1/waivers/`.
///
/// The list endpoint fills the summary fields ([name],
/// [currentVersionNumber], [currentVersionSignedCount]) and
/// leaves [currentVersion] null; the single-waiver get
/// embeds [currentVersion] (with its body).
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createToJson: false,
)
class WaiverResponse extends Equatable {
  final String waiverId;
  final String gymId;
  final String name;
  @JsonKey(fromJson: WaiverType.fromJson)
  final WaiverType waiverType;
  final String? currentVersionId;
  final int? currentVersionNumber;
  @JsonKey(defaultValue: 0)
  final int currentVersionSignedCount;

  /// DISTINCT members who signed ANY version — the catalog's headline
  /// "N signed" (a re-signer counts once).
  @JsonKey(defaultValue: 0)
  final int totalSignedCount;
  @JsonKey(defaultValue: false)
  final bool isDeleted;
  final DateTime createdAt;
  final DateTime updatedAt;
  final WaiverVersionResponse? currentVersion;

  const WaiverResponse({
    required this.waiverId,
    required this.gymId,
    required this.name,
    required this.waiverType,
    this.currentVersionId,
    this.currentVersionNumber,
    this.currentVersionSignedCount = 0,
    this.totalSignedCount = 0,
    this.isDeleted = false,
    required this.createdAt,
    required this.updatedAt,
    this.currentVersion,
  });

  factory WaiverResponse.fromJson(
    Map<String, dynamic> json,
  ) =>
      _$WaiverResponseFromJson(json);

  @override
  List<Object?> get props => [
        waiverId,
        gymId,
        name,
        waiverType,
        currentVersionId,
        currentVersionNumber,
        currentVersionSignedCount,
        totalSignedCount,
        isDeleted,
        createdAt,
        updatedAt,
        currentVersion,
      ];
}
