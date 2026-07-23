import 'package:json_annotation/json_annotation.dart';

part 'redemption_record.g.dart';

/// The approval state of a reward redemption.
///
/// Mirrors the Postgres `reward_redemption_status` enum
/// (`RewardRedemptionStatus` in
/// `Database/python_data/schema/member_reward_redemption.py`): a member's
/// request is `pending` until staff `approved` / `rejected` it. [unknown] is
/// the resilient fallback for any value the app doesn't recognise.
enum RedemptionStatus { pending, approved, rejected, unknown }

/// Resolve a backend status string to a [RedemptionStatus] without ever
/// throwing on an unrecognised value (the resilient-enum-parsing house rule).
RedemptionStatus redemptionStatusFromJson(Object? raw) {
  final value = raw is String ? raw : '';
  return RedemptionStatus.values.firstWhere(
    (s) => s.name == value,
    orElse: () => RedemptionStatus.unknown,
  );
}

/// One of the member's past reward redemptions — a row of their redemption
/// history.
///
/// Mirrors `RedemptionHistoryItem` in
/// `FastApiBackend/src/rewards/schema/rewards_schema.py`
/// (`GET /api/v1/member/gyms/{gid}/members/{mid}/redemptions`). [imageUrl] /
/// [priceLabel] join straight off `gym_rewards` (an always-matching JOIN), so
/// they're never null. [requestedAt] is kept as the backend's raw ISO
/// datetime string.
@JsonSerializable(fieldRename: FieldRename.snake, createToJson: false)
class RedemptionRecord {
  final String redemptionId;
  final String rewardId;
  final String title;
  final String imageUrl;
  final String priceLabel;
  final int pointCost;
  final String requestedAt;
  @JsonKey(fromJson: redemptionStatusFromJson)
  final RedemptionStatus status;

  const RedemptionRecord({
    required this.redemptionId,
    required this.rewardId,
    required this.title,
    required this.imageUrl,
    required this.priceLabel,
    required this.pointCost,
    required this.requestedAt,
    required this.status,
  });

  factory RedemptionRecord.fromJson(Map<String, dynamic> json) =>
      _$RedemptionRecordFromJson(json);
}
