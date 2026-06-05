import 'package:json_annotation/json_annotation.dart';

part 'waiver_create_request.g.dart';

/// Body for `POST /api/v1/waivers/` — creates a waiver and
/// publishes its first version from [body].
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createFactory: false,
)
class WaiverCreateRequest {
  final String gymId;
  final String name;
  final String body;

  const WaiverCreateRequest({
    required this.gymId,
    required this.name,
    required this.body,
  });

  Map<String, dynamic> toJson() =>
      _$WaiverCreateRequestToJson(this);
}
