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
  final String? error;

  const SettingsState({
    this.saving = false,
    this.savingTimezone = false,
    this.timezoneSavedCount = 0,
    this.error,
  });

  SettingsState copyWith({
    bool? saving,
    bool? savingTimezone,
    int? timezoneSavedCount,
    String? error,
    bool clearError = false,
  }) {
    return SettingsState(
      saving: saving ?? this.saving,
      savingTimezone: savingTimezone ?? this.savingTimezone,
      timezoneSavedCount: timezoneSavedCount ?? this.timezoneSavedCount,
      error: clearError ? null : (error ?? this.error),
    );
  }

  @override
  List<Object?> get props => [saving, savingTimezone, timezoneSavedCount, error];
}
