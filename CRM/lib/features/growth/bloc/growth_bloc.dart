import 'dart:developer';

import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/errors/exceptions.dart';
import 'package:crm/core/state/selected_gym.dart';
import 'package:crm/features/growth/bloc/growth_event.dart';
import 'package:crm/features/growth/bloc/growth_state.dart';
import 'package:crm/features/growth/data/repositories/growth_repository.dart';

/// Bloc for the Growth page.
///
/// One read, one state. The gym is read synchronously off the global
/// [selectedGym] at event-handling time (the CRM convention — no bloc
/// subscribes to that notifier; a gym switch remounts the screen with a fresh
/// `BlocProvider.create`).
class GrowthBloc extends Bloc<GrowthEvent, GrowthState> {
  final GrowthRepository _repository;

  GrowthBloc({required GrowthRepository repository})
      : _repository = repository,
        super(const GrowthState()) {
    on<GrowthLoadRequested>(_onLoadRequested);
    on<GrowthRefreshRequested>(_onRefreshRequested);
  }

  Future<void> _onLoadRequested(
    GrowthLoadRequested event,
    Emitter<GrowthState> emit,
  ) async {
    final gymId = selectedGym.gymId;
    if (gymId == null) {
      emit(state.copyWith(
        status: GrowthStatus.error,
        error: 'No gym selected.',
      ));
      return;
    }

    emit(state.copyWith(status: GrowthStatus.loading, clearError: true));
    try {
      final page = await _repository.getGrowth(gymId);
      emit(GrowthState(
        status: GrowthStatus.loaded,
        metrics: page.metrics,
        computedAt: page.computedAt,
      ));
    } catch (e, st) {
      log('GrowthBloc: getGrowth failed', error: e, stackTrace: st);
      emit(state.copyWith(
        status: GrowthStatus.error,
        error: _userMessage(e),
      ));
    }
  }

  Future<void> _onRefreshRequested(
    GrowthRefreshRequested event,
    Emitter<GrowthState> emit,
  ) async {
    final gymId = selectedGym.gymId;
    if (gymId == null || state.status == GrowthStatus.loading) return;

    try {
      final page = await _repository.getGrowth(gymId);
      emit(GrowthState(
        status: GrowthStatus.loaded,
        metrics: page.metrics,
        computedAt: page.computedAt,
      ));
    } catch (e, st) {
      // Keep the last good page — a background refresh never replaces
      // rendered metrics with an error.
      log('GrowthBloc: growth refresh failed', error: e, stackTrace: st);
    }
  }

  String _userMessage(Object e) {
    if (e is ServerException) return e.detail ?? e.message;
    if (e is NetworkException) return e.message;
    return 'Something went wrong. Please try again.';
  }
}
