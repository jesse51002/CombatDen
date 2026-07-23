import 'package:equatable/equatable.dart';

/// Events for the Growth page.
sealed class GrowthEvent extends Equatable {
  const GrowthEvent();

  @override
  List<Object?> get props => [];
}

/// Load (or reload) the current gym's metrics.
///
/// Also the retry path: dispatching it again after an error re-runs the read
/// through the loading state.
class GrowthLoadRequested extends GrowthEvent {
  const GrowthLoadRequested();
}

/// Silently re-fetch, keeping the metrics already on screen.
///
/// Unlike [GrowthLoadRequested] it does not flash a spinner, and a failed
/// refresh leaves the last good page in place instead of replacing it with an
/// error.
class GrowthRefreshRequested extends GrowthEvent {
  const GrowthRefreshRequested();
}
