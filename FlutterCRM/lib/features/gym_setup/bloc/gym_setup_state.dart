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

/// Step 2: Enter owner first/last name
class GymSetupOwnerNameStep extends GymSetupState {
  final String? errorMessage;
  final bool isSubmitting;

  const GymSetupOwnerNameStep({
    this.errorMessage,
    this.isSubmitting = false,
  });

  @override
  List<Object?> get props => [
        errorMessage,
        isSubmitting,
      ];
}

/// Setup complete — gym and owner employee exist
class GymSetupComplete extends GymSetupState {
  const GymSetupComplete();
}
