import 'package:equatable/equatable.dart';

/// Events for the gym setup wizard
sealed class GymSetupEvent extends Equatable {
  const GymSetupEvent();

  @override
  List<Object?> get props => [];
}

/// Bootstrap: check existing gym/onboarding status.
class GymSetupCheckRequested extends GymSetupEvent {
  const GymSetupCheckRequested();
}

/// Continue past the welcome step.
class GymSetupWelcomeContinued extends GymSetupEvent {
  const GymSetupWelcomeContinued();
}

/// Submit gym name (step 1).
///
/// [address] is the OPTIONAL street address typed on the same step —
/// null when the owner left the field blank (they can set it later in
/// Settings). Gym name stays the only required field here.
class GymSetupGymNameSubmitted extends GymSetupEvent {
  final String gymName;
  final String? address;

  const GymSetupGymNameSubmitted({
    required this.gymName,
    this.address,
  });

  @override
  List<Object?> get props => [gymName, address];
}

/// Submit owner name (final wizard step).
/// Triggers `POST /api/v1/gyms/`.
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

/// User tapped "Continue setup" on the resume screen.
class GymSetupResumeAccepted extends GymSetupEvent {
  const GymSetupResumeAccepted();
}

/// User tapped "Open Stripe onboarding".
class GymSetupStripeOpenRequested extends GymSetupEvent {
  const GymSetupStripeOpenRequested();
}

/// Poll tick — fired by the internal timer or
/// manually by the user tapping "Check status now".
class GymSetupStripePollNow extends GymSetupEvent {
  const GymSetupStripePollNow();
}

/// Tab/page visibility changed. The screen forwards
/// `WidgetsBindingObserver` lifecycle callbacks via
/// this event so the bloc can pause/resume polling.
class GymSetupVisibilityChanged extends GymSetupEvent {
  final bool visible;

  const GymSetupVisibilityChanged({required this.visible});

  @override
  List<Object?> get props => [visible];
}
