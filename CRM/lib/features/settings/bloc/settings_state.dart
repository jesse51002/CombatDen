import 'package:equatable/equatable.dart';

/// Lightweight state for the settings save path.
///
/// The *selected* theme itself lives in `themeController` (it drives the whole
/// app, not just this screen), so this state only tracks the in-flight save and
/// any error to surface — the appearance control reads its selection from the
/// controller.
class SettingsState extends Equatable {
  final bool saving;

  /// True while a gym timezone save is in flight — its own channel so the
  /// timezone selector can disable independently of the theme save.
  final bool savingTimezone;

  /// Bumps once per committed timezone save; a `BlocListener` watches it to
  /// surface the success SnackBar (the save is not optimistic, so the
  /// confirmation must be explicit).
  final int timezoneSavedCount;

  /// True while a Gym profile (name + logo) save is in flight — its own
  /// channel so that section can disable independently of the other saves.
  final bool savingGymProfile;

  /// Bumps once per committed Gym profile save; the section's `BlocListener`
  /// watches it to surface the success SnackBar (the save is not optimistic).
  final int gymProfileSavedCount;
  final String? error;

  const SettingsState({
    this.saving = false,
    this.savingTimezone = false,
    this.timezoneSavedCount = 0,
    this.savingGymProfile = false,
    this.gymProfileSavedCount = 0,
    this.error,
  });

  SettingsState copyWith({
    bool? saving,
    bool? savingTimezone,
    int? timezoneSavedCount,
    bool? savingGymProfile,
    int? gymProfileSavedCount,
    String? error,
    bool clearError = false,
  }) {
    return SettingsState(
      saving: saving ?? this.saving,
      savingTimezone: savingTimezone ?? this.savingTimezone,
      timezoneSavedCount: timezoneSavedCount ?? this.timezoneSavedCount,
      savingGymProfile: savingGymProfile ?? this.savingGymProfile,
      gymProfileSavedCount: gymProfileSavedCount ?? this.gymProfileSavedCount,
      error: clearError ? null : (error ?? this.error),
    );
  }

  @override
  List<Object?> get props => [
        saving,
        savingTimezone,
        timezoneSavedCount,
        savingGymProfile,
        gymProfileSavedCount,
        error,
      ];
}
