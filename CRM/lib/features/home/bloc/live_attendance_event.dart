import 'package:equatable/equatable.dart';

sealed class LiveAttendanceEvent extends Equatable {
  const LiveAttendanceEvent();

  @override
  List<Object?> get props => [];
}

/// Initial (or retry) load for [gymId] — shows the loading state.
class LiveAttendanceLoadRequested extends LiveAttendanceEvent {
  final String gymId;

  const LiveAttendanceLoadRequested(this.gymId);

  @override
  List<Object?> get props => [gymId];
}

/// Silent re-fetch (the 60s poll tick, or returning from a footer action):
/// re-emits a fresh loaded state on success, keeps the current state on
/// failure — the card never flickers back to a spinner or drops to an error
/// over one missed tick.
class LiveAttendanceRefreshRequested extends LiveAttendanceEvent {
  const LiveAttendanceRefreshRequested();
}
