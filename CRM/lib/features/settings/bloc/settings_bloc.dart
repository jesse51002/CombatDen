import 'dart:developer';

import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/state/selected_gym.dart';
import 'package:crm/core/state/theme_controller.dart';
import 'package:crm/features/settings/bloc/settings_event.dart';
import 'package:crm/features/settings/bloc/settings_state.dart';
import 'package:crm/features/settings/data/repositories/settings_repository.dart';

/// Saves the chosen CRM theme to the caller's `gym_employees` row and the
/// gym's timezone to the gym row.
///
/// The theme is applied **optimistically** to [themeController] (so the app
/// re-skins the instant a pill is tapped) and reverted if the backend save
/// fails — the same shape as the member-detail billing actions, kept tiny.
/// The timezone save is **not** optimistic: the backend commits first, then
/// [selectedGym] updates and `timezoneSavedCount` bumps for the success
/// SnackBar.
class SettingsBloc extends Bloc<SettingsEvent, SettingsState> {
  final SettingsRepository _repository;

  SettingsBloc({required SettingsRepository repository})
      : _repository = repository,
        super(const SettingsState()) {
    on<SettingsThemeModeChanged>(_onThemeModeChanged);
    on<SettingsTimezoneChanged>(_onTimezoneChanged);
    on<SettingsErrorCleared>(
      (event, emit) => emit(state.copyWith(clearError: true)),
    );
  }

  Future<void> _onThemeModeChanged(
    SettingsThemeModeChanged event,
    Emitter<SettingsState> emit,
  ) async {
    final gymId = selectedGym.gymId;
    final previous = themeController.mode;
    if (gymId == null || event.mode == previous) return;

    // Optimistic: re-skin the app now, persist next.
    themeController.setMode(event.mode);
    emit(state.copyWith(saving: true, clearError: true));

    try {
      await _repository.updateMyTheme(gymId: gymId, mode: event.mode);
      emit(state.copyWith(saving: false));
    } catch (e, stackTrace) {
      log('Failed to save theme preference', error: e, stackTrace: stackTrace);
      themeController.setMode(previous); // revert the optimistic change
      emit(
        state.copyWith(
          saving: false,
          error: 'Couldn\'t save your theme. Please try again.',
        ),
      );
    }
  }

  Future<void> _onTimezoneChanged(
    SettingsTimezoneChanged event,
    Emitter<SettingsState> emit,
  ) async {
    final gymId = selectedGym.gymId;
    if (gymId == null || event.timezone == selectedGym.timezone) return;

    // NOT optimistic: the backend commits first, then the local state updates.
    emit(state.copyWith(savingTimezone: true, clearError: true));

    try {
      await _repository.updateGymTimezone(
        gymId: gymId,
        timezone: event.timezone,
      );
      selectedGym.updateTimezone(event.timezone);
      emit(
        state.copyWith(
          savingTimezone: false,
          timezoneSavedCount: state.timezoneSavedCount + 1,
        ),
      );
    } catch (e, stackTrace) {
      log('Failed to save gym timezone', error: e, stackTrace: stackTrace);
      emit(
        state.copyWith(
          savingTimezone: false,
          error: 'Couldn\'t update the gym timezone. Please try again.',
        ),
      );
    }
  }
}
