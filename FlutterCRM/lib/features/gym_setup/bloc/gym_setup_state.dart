import 'package:equatable/equatable.dart';

/// States for the gym setup wizard
sealed class GymSetupState extends Equatable {
  const GymSetupState();

  @override
  List<Object?> get props => [];
}

/// Initial state before any check
class GymSetupInitial extends GymSetupState {
  const GymSetupInitial();
}

/// Loading during initial check
class GymSetupLoading extends GymSetupState {
  const GymSetupLoading();
}

/// Welcome step: introduce the setup process
class GymSetupWelcomeStep extends GymSetupState {
  const GymSetupWelcomeStep();
}

/// Step 1: Enter gym name
class GymSetupGymNameStep extends GymSetupState {
  final String? errorMessage;
  final bool isSubmitting;

  const GymSetupGymNameStep({
    this.errorMessage,
    this.isSubmitting = false,
  });

  @override
  List<Object?> get props => [errorMessage, isSubmitting];
}

/// Step 2: Configure rank settings
class GymSetupRankConfigStep extends GymSetupState {
  final String gymId;
  final String? errorMessage;
  final bool isSubmitting;

  const GymSetupRankConfigStep({
    required this.gymId,
    this.errorMessage,
    this.isSubmitting = false,
  });

  @override
  List<Object?> get props => [
        gymId,
        errorMessage,
        isSubmitting,
      ];
}

/// Step 3: Enter owner first/last name
class GymSetupOwnerNameStep extends GymSetupState {
  final String gymId;
  final String? errorMessage;
  final bool isSubmitting;

  const GymSetupOwnerNameStep({
    required this.gymId,
    this.errorMessage,
    this.isSubmitting = false,
  });

  @override
  List<Object?> get props => [
        gymId,
        errorMessage,
        isSubmitting,
      ];
}

/// Setup complete — both gym and profile exist
class GymSetupComplete extends GymSetupState {
  const GymSetupComplete();
}
