import 'package:json_annotation/json_annotation.dart';

part 'pending_redemption_card.g.dart';

/// A reward redemption awaiting staff approval.
///
/// Mirrors `PendingRedemptionCard` in
/// `FastApiBackend/src/members/schema/members_billing_schema.py`.
/// [requestedAt] is kept as the backend's raw ISO datetime string.
@JsonSerializable(fieldRename: FieldRename.snake, createToJson: false)
class PendingRedemptionCard {
  final String redemptionId;
  final String rewardId;
  final String title;
  final String priceLabel;
  final String imageUrl;
  final int pointCost;
  final String requestedAt;

  const PendingRedemptionCard({
    required this.redemptionId,
    required this.rewardId,
    required this.title,
    required this.priceLabel,
    required this.imageUrl,
    required this.pointCost,
    required this.requestedAt,
  });

  factory PendingRedemptionCard.fromJson(Map<String, dynamic> json) =>
      _$PendingRedemptionCardFromJson(json);
}
