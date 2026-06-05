import 'dart:developer';

import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/features/memberships/bloc/discounts/discounts_event.dart';
import 'package:crm/features/memberships/bloc/discounts/discounts_state.dart';
import 'package:crm/features/memberships/data/repositories/memberships_repository.dart';

/// Manages the gym's discount-preset catalog: list + create /
/// update / delete, each reloading the list.
class DiscountsBloc extends Bloc<DiscountsEvent, DiscountsState> {
  final MembershipsRepository _repository;

  DiscountsBloc({required MembershipsRepository repository})
      : _repository = repository,
        super(const DiscountsInitial()) {
    on<DiscountsInitRequested>(_onInitRequested);
    on<DiscountCreated>(_onCreated);
    on<DiscountUpdated>(_onUpdated);
    on<DiscountDeleted>(_onDeleted);
  }

  Future<void> _onInitRequested(
    DiscountsInitRequested event,
    Emitter<DiscountsState> emit,
  ) async {
    emit(const DiscountsLoading());
    try {
      final discounts = await _repository.listDiscounts(event.gymId);
      emit(DiscountsLoaded(gymId: event.gymId, discounts: discounts));
    } catch (e, stackTrace) {
      log('Failed to load discounts', error: e, stackTrace: stackTrace);
      emit(DiscountsError(e.toString(), gymId: event.gymId));
    }
  }

  Future<void> _onCreated(
    DiscountCreated event,
    Emitter<DiscountsState> emit,
  ) =>
      _mutateAndReload(
        emit,
        event.request.gymId,
        () => _repository.createDiscount(event.request),
      );

  Future<void> _onUpdated(
    DiscountUpdated event,
    Emitter<DiscountsState> emit,
  ) =>
      _mutateAndReload(
        emit,
        event.request.gymId,
        () => _repository.updateDiscount(event.request),
      );

  Future<void> _onDeleted(
    DiscountDeleted event,
    Emitter<DiscountsState> emit,
  ) =>
      _mutateAndReload(
        emit,
        event.gymId,
        () => _repository.deleteDiscount(event.discountId, event.gymId),
      );

  Future<void> _mutateAndReload(
    Emitter<DiscountsState> emit,
    String gymId,
    Future<void> Function() action,
  ) async {
    final current = state;
    if (current is DiscountsLoaded) {
      emit(current.copyWith(isMutating: true));
    }
    try {
      await action();
      final discounts = await _repository.listDiscounts(gymId);
      emit(DiscountsLoaded(gymId: gymId, discounts: discounts));
    } catch (e, stackTrace) {
      log('Discount mutation failed', error: e, stackTrace: stackTrace);
      if (current is DiscountsLoaded) {
        emit(current.copyWith(
          isMutating: false,
          actionError: e.toString(),
        ));
      } else {
        emit(DiscountsError(e.toString(), gymId: gymId));
      }
    }
  }
}
