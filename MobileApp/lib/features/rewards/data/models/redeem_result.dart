import 'package:json_annotation/json_annotation.dart';

import 'package:mobile_app/features/rewards/data/models/redemption_record.dart';

part 'redeem_result.g.dart';

/// The result of requesting a reward redemption — a newly-created PENDING
/// `member_reward_redemptions` row, with the member's points already debited.
///
/// Mirrors `RedemptionResponse` in
/// `FastApiBackend/src/rewards/schema/rewards_schema.py`
/// (`POST /api/v1/member/gyms/{gid}/members/{mid}/rewards/{rid}/redeem`, 201).
/// [status] is always `pending` on this path (`auto_approve` is hardwired
/// false server-side, so a member never self-approves). [requestedAt] /
/// [resolvedAt] are kept as raw ISO datetime strings; [resolvedAt] is null
/// while pending. [pointsBalanceAfter] is the balance after the debit —
/// informational only, since the authoritative balance flows from the shared
/// profile source (which the screen refreshes after a redeem).
@JsonSerializable(fieldRename: FieldRename.snake, createToJson: false)
class RedeemResult {
  final String redemptionId;
  final String memberId;
  final String rewardId;
  final String gymId;
  final int pointCost;
  final String requestedAt;
  @JsonKey(fromJson: redemptionStatusFromJson)
  final RedemptionStatus status;
  final String? resolvedAt;
  final int pointsBalanceAfter;

  const RedeemResult({
    required this.redemptionId,
    required this.memberId,
    required this.rewardId,
    required this.gymId,
    required this.pointCost,
    required this.requestedAt,
    required this.status,
    required this.pointsBalanceAfter,
    this.resolvedAt,
  });

  factory RedeemResult.fromJson(Map<String, dynamic> json) =>
      _$RedeemResultFromJson(json);
}
