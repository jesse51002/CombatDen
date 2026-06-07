import 'dart:developer';

import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/features/memberships/bloc/waivers/waivers_event.dart';
import 'package:crm/features/memberships/bloc/waivers/waivers_state.dart';
import 'package:crm/features/memberships/data/repositories/memberships_repository.dart';

/// Manages the gym's waiver catalog: list + create / update
/// (which publishes a new version on body change) / delete,
/// each reloading the list.
class WaiversBloc extends Bloc<WaiversEvent, WaiversState> {
  final MembershipsRepository _repository;

  WaiversBloc({required MembershipsRepository repository})
      : _repository = repository,
        super(const WaiversInitial()) {
    on<WaiversInitRequested>(_onInitRequested);
    on<WaiverCreated>(_onCreated);
    on<WaiverUpdated>(_onUpdated);
    on<WaiverDeleted>(_onDeleted);
  }

  Future<void> _onInitRequested(
    WaiversInitRequested event,
    Emitter<WaiversState> emit,
  ) async {
    emit(const WaiversLoading());
    try {
      final waivers = await _repository.listWaivers(event.gymId);
      emit(WaiversLoaded(gymId: event.gymId, waivers: waivers));
    } catch (e, stackTrace) {
      log('Failed to load waivers', error: e, stackTrace: stackTrace);
      emit(WaiversError(e.toString(), gymId: event.gymId));
    }
  }

  Future<void> _onCreated(WaiverCreated event, Emitter<WaiversState> emit) =>
      _mutateAndReload(
        emit,
        event.request.gymId,
        () => _repository.createWaiver(event.request),
      );

  Future<void> _onUpdated(WaiverUpdated event, Emitter<WaiversState> emit) =>
      _mutateAndReload(
        emit,
        event.request.gymId,
        () => _repository.updateWaiver(event.request),
      );

  Future<void> _onDeleted(WaiverDeleted event, Emitter<WaiversState> emit) =>
      _mutateAndReload(
        emit,
        event.gymId,
        () => _repository.deleteWaiver(event.waiverId, event.gymId),
      );

  Future<void> _mutateAndReload(
    Emitter<WaiversState> emit,
    String gymId,
    Future<void> Function() action,
  ) async {
    final current = state;
    if (current is WaiversLoaded) {
      emit(current.copyWith(isMutating: true));
    }
    try {
      await action();
      final waivers = await _repository.listWaivers(gymId);
      emit(WaiversLoaded(gymId: gymId, waivers: waivers));
    } catch (e, stackTrace) {
      log('Waiver mutation failed', error: e, stackTrace: stackTrace);
      if (current is WaiversLoaded) {
        emit(current.copyWith(
          isMutating: false,
          actionError: e.toString(),
        ));
      } else {
        emit(WaiversError(e.toString(), gymId: gymId));
      }
    }
  }
}
