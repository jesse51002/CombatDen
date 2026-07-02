import 'package:json_annotation/json_annotation.dart';

part 'waiver_update_request.g.dart';

/// Mutable waiver fields for `PUT /api/v1/waivers/`. Sending
/// [body] publishes a new immutable version; [name] renames in
/// place. Only null fields are omitted from the payload.
/// [requiresResign] is always sent — false for a minor body
/// edit (typo) that should NOT re-block prior signers; defaults
/// true (a material change).
@JsonSerializable(
  fieldRename: FieldRename.snake,
  includeIfNull: false,
  createFactory: false,
)
class WaiverUpdateData {
  final String? name;
  final String? body;

  /// When false, prior signers are NOT blocked from their next
  /// purchase even though a new version was minted. Use for
  /// typo-level fixes. Defaults true (re-sign required).
  @JsonKey(includeIfNull: false)
  final bool requiresResign;

  const WaiverUpdateData({
    this.name,
    this.body,
    this.requiresResign = true,
  });

  Map<String, dynamic> toJson() => _$WaiverUpdateDataToJson(this);
}

/// Body for `PUT /api/v1/waivers/` — identity fields plus a
/// nested [data] of changes.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  explicitToJson: true,
  createFactory: false,
)
class WaiverUpdateRequest {
  final String waiverId;
  final String gymId;
  final WaiverUpdateData data;

  const WaiverUpdateRequest({
    required this.waiverId,
    required this.gymId,
    required this.data,
  });

  Map<String, dynamic> toJson() => _$WaiverUpdateRequestToJson(this);
}
