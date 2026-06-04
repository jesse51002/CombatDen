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

/// Loading during initial bootstrap check
class GymSetupLoading extends GymSetupState {
  const GymSetupLoading();
}

/// Welcome step: introduce the setup process
class GymSetupWelcomeStep extends GymSetupState {
  final String? errorMessage;

  const GymSetupWelcomeStep({this.errorMessage});

  @override
  List<Object?> get props => [errorMessage];
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

/// Bootstrap found an in-progress gym in `pending`
/// state. User must explicitly accept to re-open the
/// hosted Stripe flow.
class GymSetupResumeStep extends GymSetupState {
  final String gymId;
  final String onboardingUrl;
  final DateTime onboardingUrlExpiresAt;
  final String? errorMessage;
  final bool isSubmitting;

  const GymSetupResumeStep({
    required this.gymId,
    required this.onboardingUrl,
    required this.onboardingUrlExpiresAt,
    this.errorMessage,
    this.isSubmitting = false,
  });

  @override
  List<Object?> get props => [
        gymId,
        onboardingUrl,
        onboardingUrlExpiresAt,
        errorMessage,
        isSubmitting,
      ];
}

/// Main Stripe onboarding screen — the poller runs
/// while the user spends most of their setup time
/// here.
class GymSetupStripeOnboardingStep extends GymSetupState {
  final String gymId;
  final String onboardingUrl;
  final DateTime onboardingUrlExpiresAt;
  final List<String> requirementsDue;
  final bool isPolling;
  final bool showBackendTroubleBanner;
  final String? errorMessage;

  const GymSetupStripeOnboardingStep({
    required this.gymId,
    required this.onboardingUrl,
    required this.onboardingUrlExpiresAt,
    this.requirementsDue = const <String>[],
    this.isPolling = false,
    this.showBackendTroubleBanner = false,
    this.errorMessage,
  });

  GymSetupStripeOnboardingStep copyWith({
    String? gymId,
    String? onboardingUrl,
    DateTime? onboardingUrlExpiresAt,
    List<String>? requirementsDue,
    bool? isPolling,
    bool? showBackendTroubleBanner,
    String? errorMessage,
    bool clearErrorMessage = false,
  }) {
    return GymSetupStripeOnboardingStep(
      gymId: gymId ?? this.gymId,
      onboardingUrl:
          onboardingUrl ?? this.onboardingUrl,
      onboardingUrlExpiresAt: onboardingUrlExpiresAt ??
          this.onboardingUrlExpiresAt,
      requirementsDue:
          requirementsDue ?? this.requirementsDue,
      isPolling: isPolling ?? this.isPolling,
      showBackendTroubleBanner: showBackendTroubleBanner ??
          this.showBackendTroubleBanner,
      errorMessage: clearErrorMessage
          ? null
          : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  List<Object?> get props => [
        gymId,
        onboardingUrl,
        onboardingUrlExpiresAt,
        requirementsDue,
        isPolling,
        showBackendTroubleBanner,
        errorMessage,
      ];
}

/// Terminal state when Stripe has disabled the gym's
/// connected account.
class GymSetupDisabledStep extends GymSetupState {
  final String gymId;
  final String? disabledReason;

  const GymSetupDisabledStep({
    required this.gymId,
    required this.disabledReason,
  });

  @override
  List<Object?> get props => [gymId, disabledReason];
}

/// Setup complete — gym is usable.
class GymSetupComplete extends GymSetupState {
  final String gymId;

  const GymSetupComplete({required this.gymId});

  @override
  List<Object?> get props => [gymId];
}
