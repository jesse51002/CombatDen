import 'package:equatable/equatable.dart';

import 'package:mobile_app/core/refresh/refresh_signal.dart';

/// Events for [RankProgressBloc].
sealed class RankProgressEvent extends Equatable {
  const RankProgressEvent();

  @override
  List<Object?> get props => [];
}

/// Load the selected member's rank-progress series (the profile graph). Also
/// the retry event on an error.
class RankProgressLoadRequested extends RankProgressEvent {
  const RankProgressLoadRequested();
}

/// Pull-to-refresh: re-fetch the series without blanking the graph that is
/// already drawn. A failure keeps the last-good series; with nothing loaded
/// the retry-able error state still surfaces.
///
/// [done] is the completion side-channel — see [RefreshSignal].
class RankProgressRefreshRequested extends RankProgressEvent {
  const RankProgressRefreshRequested([this.done]);

  final RefreshSignal? done;
}
