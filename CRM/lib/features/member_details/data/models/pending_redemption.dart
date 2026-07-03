import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'pending_redemption.g.dart';

/// A reward redemption awaiting staff approval.
///
/// Mirrors `PendingRedemptionCard` from
/// `FastApiBackend/src/members/schema/members_billing_schema.py`.
///
/// Sourced from `member_reward_redemptions` rows with
/// `status = 'pending'`; carries the redemption's own
/// [redemptionId] and [requestedAt] timestamp so staff can
/// identify and act on specific pending requests.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createToJson: false,
)
class PendingRedemption extends Equatable {
  final String redemptionId;
  final String rewardId;
  final String title;
  final String? priceLabel;
  final String? imageUrl;
  final int pointCost;
  final DateTime requestedAt;

  const PendingRedemption({
    required this.redemptionId,
    required this.rewardId,
    required this.title,
    this.priceLabel,
    this.imageUrl,
    required this.pointCost,
    required this.requestedAt,
  });

  factory PendingRedemption.fromJson(
    Map<String, dynamic> json,
  ) =>
      _$PendingRedemptionFromJson(json);

  @override
  List<Object?> get props => [
        redemptionId,
        rewardId,
        title,
        priceLabel,
        imageUrl,
        pointCost,
        requestedAt,
      ];
}
