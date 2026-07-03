import 'package:equatable/equatable.dart';

/// Lightweight state for the "Set as app theme" save path.
///
/// The *saved* design itself lives on `selectedGym.savedThemeDesignId` (it's
/// read by the whole Theme tab to show the checkmark state), so this state only
/// tracks the in-flight save, a monotonic saved counter for the success
/// SnackBar, and any error to surface.
class SetAppThemeState extends Equatable {
  final bool saving;

  /// Bumps once per committed save; a `BlocListener` watches it to surface the
  /// success SnackBar (the save is not optimistic, so the confirmation must be
  /// explicit).
  final int savedCount;
  final String? error;

  const SetAppThemeState({
    this.saving = false,
    this.savedCount = 0,
    this.error,
  });

  SetAppThemeState copyWith({
    bool? saving,
    int? savedCount,
    String? error,
    bool clearError = false,
  }) {
    return SetAppThemeState(
      saving: saving ?? this.saving,
      savedCount: savedCount ?? this.savedCount,
      error: clearError ? null : (error ?? this.error),
    );
  }

  @override
  List<Object?> get props => [saving, savedCount, error];
}
