import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'batch_check_in_request.g.dart';

/// Body for the batch staff check-in
/// (`POST /api/v1/classes/{class_id}/occurrences/{occurrence_date}/`
/// `checkin-batch`). The occurrence is addressed by the PATH params; this body
/// carries only the gym (auth gate), the members to check in, and the override.
///
/// Mirrors the backend `BatchCheckinRequest`. [allowOverride] forces every
/// member past the eligibility, punch-card, and room-capacity gates (front-desk
/// coverage — retroactive / over-capacity / depleted).
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createFactory: false,
)
class BatchCheckInRequest extends Equatable {
  final String gymId;
  final List<String> memberIds;
  final bool allowOverride;

  const BatchCheckInRequest({
    required this.gymId,
    required this.memberIds,
    this.allowOverride = false,
  });

  Map<String, dynamic> toJson() => _$BatchCheckInRequestToJson(this);

  @override
  List<Object?> get props => [gymId, memberIds, allowOverride];
}
