import 'package:equatable/equatable.dart';

/// Lightweight state for the settings save path.
///
/// The *selected* theme itself lives in `themeController` (it drives the whole
/// app, not just this screen), so this state only tracks the in-flight save and
/// any error to surface — the appearance control reads its selection from the
/// controller.
class SettingsState extends Equatable {
  final bool saving;
  final String? error;

  const SettingsState({this.saving = false, this.error});

  SettingsState copyWith({
    bool? saving,
    String? error,
    bool clearError = false,
  }) {
    return SettingsState(
      saving: saving ?? this.saving,
      error: clearError ? null : (error ?? this.error),
    );
  }

  @override
  List<Object?> get props => [saving, error];
}
