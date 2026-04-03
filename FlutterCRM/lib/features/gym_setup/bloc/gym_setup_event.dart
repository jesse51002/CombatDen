import 'package:equatable/equatable.dart';

/// Events for the gym setup wizard
sealed class GymSetupEvent extends Equatable {
  const GymSetupEvent();

  @override
  List<Object?> get props => [];
}

/// Check existing gym and profile status
class GymSetupCheckRequested extends GymSetupEvent {
  const GymSetupCheckRequested();
}

/// Continue past the welcome step
class GymSetupWelcomeContinued extends GymSetupEvent {
  const GymSetupWelcomeContinued();
}

/// Submit gym name (step 1)
class GymSetupGymNameSubmitted extends GymSetupEvent {
  final String gymName;

  const GymSetupGymNameSubmitted({
    required this.gymName,
  });

  @override
  List<Object?> get props => [gymName];
}

/// Submit owner name (final step, triggers gym creation)
class GymSetupOwnerNameSubmitted extends GymSetupEvent {
  final String firstName;
  final String lastName;

  const GymSetupOwnerNameSubmitted({
    required this.firstName,
    required this.lastName,
  });

  @override
  List<Object?> get props => [firstName, lastName];
}
