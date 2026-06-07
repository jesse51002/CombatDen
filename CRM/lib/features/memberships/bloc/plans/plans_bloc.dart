import 'dart:developer';

import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/features/memberships/bloc/plans/plans_event.dart';
import 'package:crm/features/memberships/bloc/plans/plans_state.dart';
import 'package:crm/features/memberships/data/repositories/memberships_repository.dart';

/// Manages the gym's membership-plan catalog: list + create /
/// update / set-price / delete, each reloading the list.
class PlansBloc extends Bloc<PlansEvent, PlansState> {
  final MembershipsRepository _repository;

  PlansBloc({required MembershipsRepository repository})
      : _repository = repository,
        super(const PlansInitial()) {
    on<PlansInitRequested>(_onInitRequested);
    on<PlanCreated>(_onCreated);
    on<PlanUpdated>(_onUpdated);
    on<PlanPriceSet>(_onPriceSet);
    on<PlanDeleted>(_onDeleted);
  }

  Future<void> _onInitRequested(
    PlansInitRequested event,
    Emitter<PlansState> emit,
  ) async {
    emit(const PlansLoading());
    try {
      final plans = await _repository.listPlans(event.gymId);
      emit(PlansLoaded(gymId: event.gymId, plans: plans));
    } catch (e, stackTrace) {
      log('Failed to load plans', error: e, stackTrace: stackTrace);
      emit(PlansError(e.toString(), gymId: event.gymId));
    }
  }

  Future<void> _onCreated(PlanCreated event, Emitter<PlansState> emit) =>
      _mutateAndReload(
        emit,
        event.request.gymId,
        () => _repository.createPlan(event.request),
      );

  Future<void> _onUpdated(PlanUpdated event, Emitter<PlansState> emit) =>
      _mutateAndReload(
        emit,
        event.request.gymId,
        () => _repository.updatePlan(event.request),
      );

  Future<void> _onPriceSet(PlanPriceSet event, Emitter<PlansState> emit) =>
      _mutateAndReload(
        emit,
        event.request.gymId,
        () => _repository.setPlanPrice(event.request),
      );

  Future<void> _onDeleted(PlanDeleted event, Emitter<PlansState> emit) =>
      _mutateAndReload(
        emit,
        event.gymId,
        () => _repository.deletePlan(event.planId, event.gymId),
      );

  /// Runs [action], then reloads the list. Surfaces a failed
  /// mutation via [PlansLoaded.actionError] without dropping the
  /// list (or as [PlansError] if there is no list yet).
  Future<void> _mutateAndReload(
    Emitter<PlansState> emit,
    String gymId,
    Future<void> Function() action,
  ) async {
    final current = state;
    if (current is PlansLoaded) {
      emit(current.copyWith(isMutating: true));
    }
    try {
      await action();
      final plans = await _repository.listPlans(gymId);
      emit(PlansLoaded(gymId: gymId, plans: plans));
    } catch (e, stackTrace) {
      log('Plan mutation failed', error: e, stackTrace: stackTrace);
      if (current is PlansLoaded) {
        emit(current.copyWith(
          isMutating: false,
          actionError: e.toString(),
        ));
      } else {
        emit(PlansError(e.toString(), gymId: gymId));
      }
    }
  }
}
