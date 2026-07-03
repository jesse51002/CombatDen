import 'package:json_annotation/json_annotation.dart';

part 'pending_redemption_item.g.dart';

/// One row from the gym-wide pending redemption queue.
/// Mirrors `PendingRedemptionItem` from
/// `FastApiBackend/src/rewards/schema/rewards_schema.py`.
@JsonSerializable(fieldRename: FieldRename.snake)
class PendingRedemptionItem {
  final String redemptionId;
  final String memberId;
  final String memberName;
  final String rewardTitle;
  final String? rewardImageUrl;
  final int pointCost;
  final DateTime requestedAt;

  const PendingRedemptionItem({
    required this.redemptionId,
    required this.memberId,
    required this.memberName,
    required this.rewardTitle,
    this.rewardImageUrl,
    required this.pointCost,
    required this.requestedAt,
  });

  factory PendingRedemptionItem.fromJson(Map<String, dynamic> json) =>
      _$PendingRedemptionItemFromJson(json);

  Map<String, dynamic> toJson() => _$PendingRedemptionItemToJson(this);
}
