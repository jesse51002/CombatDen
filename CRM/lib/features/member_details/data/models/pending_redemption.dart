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
/// [redemptionId] and [redeemedAt] timestamp so staff can
/// identify and act on specific pending requests.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createToJson: false,
)
class PendingRedemption extends Equatable {
  final String redemptionId;
  final String rewardId;
  final String title;
  final String? amountOff;
  final String? imageUrl;
  final int pointCost;
  final DateTime redeemedAt;

  const PendingRedemption({
    required this.redemptionId,
    required this.rewardId,
    required this.title,
    this.amountOff,
    this.imageUrl,
    required this.pointCost,
    required this.redeemedAt,
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
        amountOff,
        imageUrl,
        pointCost,
        redeemedAt,
      ];
}
