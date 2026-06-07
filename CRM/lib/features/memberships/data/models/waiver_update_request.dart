import 'package:json_annotation/json_annotation.dart';

part 'waiver_update_request.g.dart';

/// Mutable waiver fields for `PUT /api/v1/waivers/`. Sending
/// [body] publishes a new immutable version (members must
/// re-sign); [name] renames in place. Only non-null fields
/// are sent.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  includeIfNull: false,
  createFactory: false,
)
class WaiverUpdateData {
  final String? name;
  final String? body;

  const WaiverUpdateData({this.name, this.body});

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
