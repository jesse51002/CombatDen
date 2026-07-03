import 'package:equatable/equatable.dart';

/// Events for the "Set as app theme" save path.
sealed class SetAppThemeEvent extends Equatable {
  const SetAppThemeEvent();

  @override
  List<Object?> get props => [];
}

/// The admin pressed "Set as app theme": persist [designId] as the gym's
/// branding (`gyms.theme_design_id`). NOT optimistic — the backend commits
/// first, then `selectedGym.savedThemeDesignId` updates.
class SetAppThemeRequested extends SetAppThemeEvent {
  final String designId;

  const SetAppThemeRequested(this.designId);

  @override
  List<Object?> get props => [designId];
}

/// Dismiss the inline error after a failed save was surfaced.
class SetAppThemeErrorCleared extends SetAppThemeEvent {
  const SetAppThemeErrorCleared();
}
