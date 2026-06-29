import 'dart:developer';

import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/errors/exceptions.dart';
import 'package:crm/core/state/selected_gym.dart';
import 'package:crm/features/presets/bloc/presets_event.dart';
import 'package:crm/features/presets/bloc/presets_state.dart';
import 'package:crm/features/presets/data/repositories/presets_repository.dart';

/// Bloc for the gym presets Settings section.
///
/// Manages the template catalog browse + the single-template import action.
/// On a successful import it updates [selectedGym.videoGymId] so the
/// member-app preview reflects the imported gym immediately.
class PresetsBloc extends Bloc<PresetsEvent, PresetsState> {
  final PresetsRepository _repository;

  PresetsBloc({required PresetsRepository repository})
      : _repository = repository,
        super(const PresetsState()) {
    on<PresetsTemplatesRequested>(_onTemplatesRequested);
    on<PresetsTemplateSelected>(_onTemplateSelected);
    on<PresetsImportRequested>(_onImportRequested);
    on<PresetsErrorCleared>(
      (_, emit) => emit(state.copyWith(clearError: true)),
    );
  }

  Future<void> _onTemplatesRequested(
    PresetsTemplatesRequested event,
    Emitter<PresetsState> emit,
  ) async {
    if (state.catalogStatus == PresetsCatalogStatus.loading) return;
    emit(state.copyWith(catalogStatus: PresetsCatalogStatus.loading));
    try {
      final templates = await _repository.listTemplates();
      emit(
        state.copyWith(
          catalogStatus: PresetsCatalogStatus.loaded,
          templates: templates,
        ),
      );
    } catch (e, st) {
      log('PresetsBloc: template catalog load failed', error: e, stackTrace: st);
      emit(
        state.copyWith(
          catalogStatus: PresetsCatalogStatus.error,
          error: _userMessage(e),
        ),
      );
    }
  }

  void _onTemplateSelected(
    PresetsTemplateSelected event,
    Emitter<PresetsState> emit,
  ) {
    emit(
      state.copyWith(
        selectedVideoGymId: event.videoGymId,
        // Reset any prior import result so the UI reverts to "Apply preset".
        importStatus: PresetsImportStatus.idle,
        clearImportResult: true,
        clearError: true,
      ),
    );
  }

  Future<void> _onImportRequested(
    PresetsImportRequested event,
    Emitter<PresetsState> emit,
  ) async {
    final gymId = selectedGym.gymId;
    final videoGymId = state.selectedVideoGymId;
    if (gymId == null || videoGymId == null) return;
    if (state.importStatus == PresetsImportStatus.importing) return;

    emit(
      state.copyWith(
        importStatus: PresetsImportStatus.importing,
        clearError: true,
      ),
    );
    try {
      final result = await _repository.importPreset(
        gymId: gymId,
        videoGymId: videoGymId,
      );
      // Refresh the preview surfaces (classes / rewards / videos) to reflect the
      // imported content. Theme is intentionally NOT applied here — that's the
      // Theme tab's job; the imported design is persisted server-side.
      selectedGym.setVideoGymId(videoGymId: videoGymId);
      emit(
        state.copyWith(
          importStatus: PresetsImportStatus.success,
          importResult: result,
        ),
      );
    } catch (e, st) {
      log('PresetsBloc: import failed', error: e, stackTrace: st);
      emit(
        state.copyWith(
          importStatus: PresetsImportStatus.error,
          error: _userMessage(e),
        ),
      );
    }
  }

  String _userMessage(Object e) {
    if (e is ServerException) {
      return e.detail ?? e.message;
    }
    if (e is NetworkException) return e.message;
    return 'Something went wrong. Please try again.';
  }
}
