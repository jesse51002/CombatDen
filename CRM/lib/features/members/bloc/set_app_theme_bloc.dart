import 'dart:developer';

import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/state/selected_gym.dart';
import 'package:crm/features/members/bloc/set_app_theme_event.dart';
import 'package:crm/features/members/bloc/set_app_theme_state.dart';
import 'package:crm/features/members/data/gym_theme_repository.dart';

/// Persists the gym's chosen ThemeService design id to `gyms.theme_design_id`.
///
/// **Not optimistic** (mirrors the Settings gym-timezone save): the backend
/// commits first, then `selectedGym.savedThemeDesignId` updates and
/// `savedCount` bumps for the success SnackBar. The active gym id is read off
/// the global [selectedGym] singleton.
class SetAppThemeBloc extends Bloc<SetAppThemeEvent, SetAppThemeState> {
  final GymThemeRepository _repository;

  SetAppThemeBloc({required GymThemeRepository repository})
      : _repository = repository,
        super(const SetAppThemeState()) {
    on<SetAppThemeRequested>(_onRequested);
    on<SetAppThemeErrorCleared>(
      (event, emit) => emit(state.copyWith(clearError: true)),
    );
  }

  Future<void> _onRequested(
    SetAppThemeRequested event,
    Emitter<SetAppThemeState> emit,
  ) async {
    final gymId = selectedGym.gymId;
    // No real gym (public browser) or a no-op (already the saved theme): ignore.
    if (gymId == null ||
        event.designId.isEmpty ||
        event.designId == selectedGym.savedThemeDesignId) {
      return;
    }

    emit(state.copyWith(saving: true, clearError: true));

    try {
      await _repository.saveGymTheme(
        gymId: gymId,
        themeDesignId: event.designId,
      );
      selectedGym.updateSavedThemeDesignId(event.designId);
      emit(
        state.copyWith(
          saving: false,
          savedCount: state.savedCount + 1,
        ),
      );
    } catch (e, stackTrace) {
      log('Failed to save app theme', error: e, stackTrace: stackTrace);
      emit(
        state.copyWith(
          saving: false,
          error: 'Couldn\'t save the app theme. Please try again.',
        ),
      );
    }
  }
}
