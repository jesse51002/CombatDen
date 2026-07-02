import 'package:equatable/equatable.dart';

/// Events for the dashboard Upcoming Classes section.
sealed class UpcomingClassesEvent extends Equatable {
  const UpcomingClassesEvent();

  @override
  List<Object?> get props => [];
}

/// Load (or reload) the upcoming class occurrences for [gymId].
class UpcomingClassesLoadRequested extends UpcomingClassesEvent {
  final String gymId;

  const UpcomingClassesLoadRequested(this.gymId);

  @override
  List<Object?> get props => [gymId];
}
