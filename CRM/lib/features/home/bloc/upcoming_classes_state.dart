import 'package:equatable/equatable.dart';

import 'package:crm/features/schedule/data/models/effective_class_instance.dart';

/// States for the dashboard Upcoming Classes section.
sealed class UpcomingClassesState extends Equatable {
  const UpcomingClassesState();

  @override
  List<Object?> get props => [];
}

class UpcomingClassesInitial extends UpcomingClassesState {
  const UpcomingClassesInitial();
}

class UpcomingClassesLoading extends UpcomingClassesState {
  const UpcomingClassesLoading();
}

/// The filtered, sorted, non-cancelled upcoming occurrences. The card maps
/// these into day groups for display (kept out of the bloc so the data layer
/// stays presentation-free).
class UpcomingClassesLoaded extends UpcomingClassesState {
  final List<EffectiveClassInstance> instances;

  const UpcomingClassesLoaded(this.instances);

  @override
  List<Object?> get props => [instances];
}

class UpcomingClassesError extends UpcomingClassesState {
  final String message;
  final String gymId;

  const UpcomingClassesError(this.message, {required this.gymId});

  @override
  List<Object?> get props => [message, gymId];
}
