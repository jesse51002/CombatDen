import 'package:equatable/equatable.dart';

/// Events for the rewards feature — catalog CRUD + redemption queue actions.
sealed class RewardsEvent extends Equatable {
  const RewardsEvent();

  @override
  List<Object?> get props => [];
}

/// Load (or reload) the catalog + pending queue.
class RewardsLoadRequested extends RewardsEvent {
  const RewardsLoadRequested();
}

/// Create a new reward for the current gym.
///
/// [priceLabel] is required — the backend requires a value badge on every
/// reward, and the form validates it non-empty before dispatching.
class RewardCreateRequested extends RewardsEvent {
  final String title;
  final int pointCost;
  final String priceLabel;
  final String? imageUrl;

  const RewardCreateRequested({
    required this.title,
    required this.pointCost,
    required this.priceLabel,
    this.imageUrl,
  });

  @override
  List<Object?> get props => [
    title,
    pointCost,
    priceLabel,
    imageUrl,
  ];
}

/// Update mutable fields on an existing reward.
class RewardUpdateRequested extends RewardsEvent {
  final String rewardId;
  final String? title;
  final int? pointCost;
  final String? priceLabel;
  final String? imageUrl;
  final bool? isActive;

  const RewardUpdateRequested({
    required this.rewardId,
    this.title,
    this.pointCost,
    this.priceLabel,
    this.imageUrl,
    this.isActive,
  });

  @override
  List<Object?> get props => [
    rewardId,
    title,
    pointCost,
    priceLabel,
    imageUrl,
    isActive,
  ];
}

/// Soft-delete a reward (sets is_active=false).
class RewardDeleteRequested extends RewardsEvent {
  final String rewardId;

  const RewardDeleteRequested(this.rewardId);

  @override
  List<Object?> get props => [rewardId];
}

/// Approve a pending redemption.
class RedemptionApproveRequested extends RewardsEvent {
  final String redemptionId;

  const RedemptionApproveRequested(this.redemptionId);

  @override
  List<Object?> get props => [redemptionId];
}

/// Reject a pending redemption (refunds points).
class RedemptionRejectRequested extends RewardsEvent {
  final String redemptionId;

  const RedemptionRejectRequested(this.redemptionId);

  @override
  List<Object?> get props => [redemptionId];
}

/// Dismiss an error so the UI can retry.
class RewardsErrorCleared extends RewardsEvent {
  const RewardsErrorCleared();
}
