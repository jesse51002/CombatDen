import 'package:equatable/equatable.dart';

/// Events for [HomeBloc].
sealed class HomeEvent extends Equatable {
  const HomeEvent();

  @override
  List<Object?> get props => [];
}

/// Initial load of the board window + the member's open reservations.
class HomeLoadRequested extends HomeEvent {
  const HomeLoadRequested();
}

/// Re-fetch the current window WITHOUT blanking the screen — pull-to-refresh,
/// and the return from the class detail (a reservation may have changed).
class HomeRefreshRequested extends HomeEvent {
  const HomeRefreshRequested();
}

/// Grow the loaded window by another page of days (the continuous scroll
/// reached the last loaded day). No-op once the cap is hit.
class HomeExtendRequested extends HomeEvent {
  const HomeExtendRequested();
}
