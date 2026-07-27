import 'package:equatable/equatable.dart';

import 'package:mobile_app/features/rewards/data/models/redemption_record.dart';
import 'package:mobile_app/features/rewards/data/models/reward_item.dart';

enum RewardsStatus { initial, loading, loaded, error }

/// The single state of [RewardsBloc]: the gym's active reward catalog and the
/// member's own redemption history, plus the in-flight / result signals of a
/// redeem request.
///
/// [redeemSuccessToken] is a monotonic counter the screen watches to fire a
/// one-shot confirmation — the SnackBar plus the `MemberProfileRefreshRequested`
/// that refreshes the balance — the every-mutation-ends-in-a-visible-
/// confirmation rule. The points BALANCE is NOT owned here: it lives on the
/// shared MemberProfileBloc.
class RewardsState extends Equatable {
  const RewardsState({
    this.status = RewardsStatus.initial,
    this.catalog = const [],
    this.redemptions = const [],
    this.isRedeeming = false,
    this.errorMessage,
    this.redeemError,
    this.redeemSuccessToken = 0,
  });

  final RewardsStatus status;

  /// The gym's active reward catalog (drives the Points Store grid).
  final List<RewardItem> catalog;

  /// The member's own redemptions (drives the My Rewards grid).
  final List<RedemptionRecord> redemptions;

  /// A redeem request is in flight (guards against a double-submit).
  final bool isRedeeming;

  /// The retry-able load error (catalog fetch failed).
  final String? errorMessage;

  /// The last redeem request's error detail (e.g. "Not enough points"),
  /// surfaced as a SnackBar — distinct from the fatal [errorMessage].
  final String? redeemError;

  final int redeemSuccessToken;

  RewardsState copyWith({
    RewardsStatus? status,
    List<RewardItem>? catalog,
    List<RedemptionRecord>? redemptions,
    bool? isRedeeming,
    String? errorMessage,
    String? redeemError,
    int? redeemSuccessToken,
    bool clearError = false,
    bool clearRedeemError = false,
  }) {
    return RewardsState(
      status: status ?? this.status,
      catalog: catalog ?? this.catalog,
      redemptions: redemptions ?? this.redemptions,
      isRedeeming: isRedeeming ?? this.isRedeeming,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      redeemError: clearRedeemError ? null : (redeemError ?? this.redeemError),
      redeemSuccessToken: redeemSuccessToken ?? this.redeemSuccessToken,
    );
  }

  @override
  List<Object?> get props => [
        status,
        catalog,
        redemptions,
        isRedeeming,
        errorMessage,
        redeemError,
        redeemSuccessToken,
      ];
}
