import 'package:equatable/equatable.dart';

import 'package:mobile_app/core/refresh/refresh_signal.dart';

/// Events for [RewardsBloc].
sealed class RewardsEvent extends Equatable {
  const RewardsEvent();

  @override
  List<Object?> get props => [];
}

/// Initial load of the gym's active catalog + the member's redemption history.
class RewardsLoadRequested extends RewardsEvent {
  const RewardsLoadRequested();
}

/// Pull-to-refresh: re-fetch the catalog + redemptions WITHOUT blanking a
/// screen that already has content (the distinction from
/// [RewardsLoadRequested], which flips to the loading state). A failure while
/// content is up keeps the last-good grids; a failure with nothing loaded
/// still surfaces the retry-able error state, because there is nothing to
/// preserve and an empty screen with no explanation is worse.
///
/// [done] is the completion side-channel — see [RefreshSignal].
class RewardsRefreshRequested extends RewardsEvent {
  const RewardsRefreshRequested([this.done]);

  final RefreshSignal? done;
}

/// Request a redemption of [rewardId] with the member's points. The UI already
/// disables this when the member can't afford it; the bloc still surfaces a
/// backend 4xx (e.g. insufficient points) rather than crashing.
class RewardsRedeemRequested extends RewardsEvent {
  const RewardsRedeemRequested({required this.rewardId});

  final String rewardId;

  @override
  List<Object?> get props => [rewardId];
}
