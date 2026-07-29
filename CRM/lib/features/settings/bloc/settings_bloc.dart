import 'dart:developer';

import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/state/selected_gym.dart';
import 'package:crm/core/state/theme_controller.dart';
import 'package:crm/features/settings/bloc/settings_event.dart';
import 'package:crm/features/settings/bloc/settings_state.dart';
import 'package:crm/features/settings/data/repositories/settings_repository.dart';

/// Saves the chosen CRM theme to the caller's `gym_employees` row, and the
/// gym's timezone and profile (name + address + logo) to the gym row.
///
/// The theme is applied **optimistically** to [themeController] (so the app
/// re-skins the instant a pill is tapped) and reverted if the backend save
/// fails — the same shape as the member-detail billing actions, kept tiny.
/// The timezone and Gym profile saves are **not** optimistic: the backend
/// commits first, then [selectedGym] updates and the matching saved-count
/// bumps for the success confirmation (a SnackBar for the timezone, the
/// section's own inline "Saved" status for the Gym profile, which auto-saves
/// and would make a SnackBar per commit noisy).
///
/// The Gym profile handler runs **sequentially** (see the transformer in the
/// constructor) because it is driven by auto-save, not a button.
class SettingsBloc extends Bloc<SettingsEvent, SettingsState> {
  final SettingsRepository _repository;

  SettingsBloc({required SettingsRepository repository})
      : _repository = repository,
        super(const SettingsState()) {
    on<SettingsThemeModeChanged>(_onThemeModeChanged);
    on<SettingsTimezoneChanged>(_onTimezoneChanged);
    // SEQUENTIAL, not the bloc default (concurrent): the Gym profile
    // auto-saves on every field blur and on every logo pick, so two commits
    // can be a keystroke apart (blur the name, immediately blur the
    // address). `asyncExpand` queues each save behind the one in flight, so
    // the second never races the first and always sees the committed
    // `selectedGym` values its no-op guard compares against.
    on<GymProfileSaveRequested>(
      _onGymProfileSave,
      transformer: (events, mapper) => events.asyncExpand(mapper),
    );
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

  Future<void> _onGymProfileSave(
    GymProfileSaveRequested event,
    Emitter<SettingsState> emit,
  ) async {
    final gymId = selectedGym.gymId;
    if (gymId == null) return;
    // No-op guard: skip the round trip when nothing actually changed.
    if (event.gymName == selectedGym.gymName &&
        event.address == selectedGym.address &&
        event.logoUrl == selectedGym.logoUrl) {
      return;
    }

    // NOT optimistic: the backend commits first, then the local state updates.
    emit(state.copyWith(savingGymProfile: true, clearError: true));

    try {
      await _repository.updateGymProfile(
        gymId: gymId,
        gymName: event.gymName,
        address: event.address,
        logoUrl: event.logoUrl,
      );
      selectedGym.updateGymName(event.gymName);
      selectedGym.updateAddress(event.address);
      selectedGym.updateLogoUrl(event.logoUrl);
      emit(
        state.copyWith(
          savingGymProfile: false,
          gymProfileSavedCount: state.gymProfileSavedCount + 1,
        ),
      );
    } catch (e, stackTrace) {
      log('Failed to save gym profile', error: e, stackTrace: stackTrace);
      emit(
        state.copyWith(
          savingGymProfile: false,
          error: 'Couldn\'t update your gym profile. Please try again.',
        ),
      );
    }
  }
}
