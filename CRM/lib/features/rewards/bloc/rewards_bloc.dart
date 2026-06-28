import 'dart:developer';

import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/errors/exceptions.dart';
import 'package:crm/core/state/selected_gym.dart';
import 'package:crm/features/rewards/bloc/rewards_event.dart';
import 'package:crm/features/rewards/bloc/rewards_state.dart';
import 'package:crm/features/rewards/data/models/pending_redemption_item.dart';
import 'package:crm/features/rewards/data/models/reward_response.dart';
import 'package:crm/features/rewards/data/repositories/rewards_repository.dart';

/// Bloc for the Loyalty tab's rewards catalog and redemption queue.
///
/// Manages the gym's reward catalog (create/update/delete) and the pending
/// redemption approval queue (approve/reject). All mutations end in a
/// visible terminal state tracked by [RewardsState.catalogSuccessToken] and
/// [RewardsState.pendingSuccessToken] for dialog-level success detection.
class RewardsBloc extends Bloc<RewardsEvent, RewardsState> {
  final RewardsRepository _repository;

  RewardsBloc({required RewardsRepository repository})
      : _repository = repository,
        super(const RewardsState()) {
    on<RewardsLoadRequested>(_onLoadRequested);
    on<RewardCreateRequested>(_onCreateRequested);
    on<RewardUpdateRequested>(_onUpdateRequested);
    on<RewardDeleteRequested>(_onDeleteRequested);
    on<RedemptionApproveRequested>(_onApproveRequested);
    on<RedemptionRejectRequested>(_onRejectRequested);
    on<RewardsErrorCleared>(
      (_, emit) => emit(
        state.copyWith(
          clearCatalogError: true,
          clearPendingError: true,
          clearMutationError: true,
          redemptionAlreadyDecided: false,
        ),
      ),
    );
  }

  String? get _gymId => selectedGym.gymId;

  Future<void> _onLoadRequested(
    RewardsLoadRequested event,
    Emitter<RewardsState> emit,
  ) async {
    final gymId = _gymId;
    if (gymId == null) return;

    emit(state.copyWith(
      catalogStatus: RewardsCatalogStatus.loading,
      pendingStatus: RewardsPendingStatus.loading,
      clearCatalogError: true,
      clearPendingError: true,
    ));

    // Start both futures concurrently then await sequentially.
    final rewardsFuture = _repository.listRewards(gymId);
    final pendingFuture = _repository.listPending(gymId);

    late RewardsCatalogStatus catalogStatus;
    List<RewardResponse> rewards = const [];
    String? catalogError;

    try {
      rewards = await rewardsFuture;
      catalogStatus = RewardsCatalogStatus.loaded;
    } catch (e, st) {
      log('RewardsBloc: listRewards failed', error: e, stackTrace: st);
      catalogStatus = RewardsCatalogStatus.error;
      catalogError = _userMessage(e);
    }

    late RewardsPendingStatus pendingStatus;
    List<PendingRedemptionItem> pendingItems = const [];
    String? pendingError;

    try {
      pendingItems = await pendingFuture;
      pendingStatus = RewardsPendingStatus.loaded;
    } catch (e, st) {
      log('RewardsBloc: listPending failed', error: e, stackTrace: st);
      pendingStatus = RewardsPendingStatus.error;
      pendingError = _userMessage(e);
    }

    emit(state.copyWith(
      catalogStatus: catalogStatus,
      rewards: rewards,
      catalogError: catalogError,
      pendingStatus: pendingStatus,
      pendingItems: pendingItems,
      pendingError: pendingError,
    ));
  }

  Future<void> _onCreateRequested(
    RewardCreateRequested event,
    Emitter<RewardsState> emit,
  ) async {
    final gymId = _gymId;
    if (gymId == null || state.isMutating) return;

    emit(state.copyWith(isMutating: true, clearMutationError: true));
    try {
      final reward = await _repository.createReward(
        gymId: gymId,
        title: event.title,
        pointCost: event.pointCost,
        amountOff: event.amountOff,
        priceLabel: event.priceLabel,
        imageUrl: event.imageUrl,
      );
      emit(state.copyWith(
        isMutating: false,
        rewards: [...state.rewards, reward],
        catalogSuccessToken: state.catalogSuccessToken + 1,
      ));
    } catch (e, st) {
      log('RewardsBloc: createReward failed', error: e, stackTrace: st);
      emit(state.copyWith(isMutating: false, mutationError: _userMessage(e)));
    }
  }

  Future<void> _onUpdateRequested(
    RewardUpdateRequested event,
    Emitter<RewardsState> emit,
  ) async {
    if (state.isMutating) return;

    emit(state.copyWith(isMutating: true, clearMutationError: true));
    try {
      final reward = await _repository.updateReward(
        event.rewardId,
        title: event.title,
        pointCost: event.pointCost,
        amountOff: event.amountOff,
        priceLabel: event.priceLabel,
        imageUrl: event.imageUrl,
        isActive: event.isActive,
      );
      final updated = state.rewards.toList();
      final idx = updated.indexWhere((r) => r.rewardId == reward.rewardId);
      if (idx >= 0) {
        updated[idx] = reward;
      } else {
        updated.add(reward);
      }
      emit(state.copyWith(
        isMutating: false,
        rewards: updated,
        catalogSuccessToken: state.catalogSuccessToken + 1,
      ));
    } catch (e, st) {
      log('RewardsBloc: updateReward failed', error: e, stackTrace: st);
      emit(state.copyWith(isMutating: false, mutationError: _userMessage(e)));
    }
  }

  Future<void> _onDeleteRequested(
    RewardDeleteRequested event,
    Emitter<RewardsState> emit,
  ) async {
    if (state.isMutating) return;

    emit(state.copyWith(isMutating: true, clearMutationError: true));
    try {
      await _repository.deleteReward(event.rewardId);
      emit(state.copyWith(
        isMutating: false,
        rewards: state.rewards
            .where((r) => r.rewardId != event.rewardId)
            .toList(),
        catalogSuccessToken: state.catalogSuccessToken + 1,
      ));
    } catch (e, st) {
      log('RewardsBloc: deleteReward failed', error: e, stackTrace: st);
      emit(state.copyWith(isMutating: false, mutationError: _userMessage(e)));
    }
  }

  Future<void> _onApproveRequested(
    RedemptionApproveRequested event,
    Emitter<RewardsState> emit,
  ) async {
    if (state.isMutating) return;
    emit(state.copyWith(isMutating: true, clearMutationError: true));
    try {
      await _repository.approve(event.redemptionId);
      emit(state.copyWith(
        isMutating: false,
        pendingItems: state.pendingItems
            .where((r) => r.redemptionId != event.redemptionId)
            .toList(),
        pendingSuccessToken: state.pendingSuccessToken + 1,
      ));
    } on RedemptionAlreadyDecidedException {
      await _refreshPendingOnAlreadyDecided(emit);
    } catch (e, st) {
      log('RewardsBloc: approve failed', error: e, stackTrace: st);
      emit(state.copyWith(isMutating: false, mutationError: _userMessage(e)));
    }
  }

  Future<void> _onRejectRequested(
    RedemptionRejectRequested event,
    Emitter<RewardsState> emit,
  ) async {
    if (state.isMutating) return;
    emit(state.copyWith(isMutating: true, clearMutationError: true));
    try {
      await _repository.reject(event.redemptionId);
      emit(state.copyWith(
        isMutating: false,
        pendingItems: state.pendingItems
            .where((r) => r.redemptionId != event.redemptionId)
            .toList(),
        pendingSuccessToken: state.pendingSuccessToken + 1,
      ));
    } on RedemptionAlreadyDecidedException {
      await _refreshPendingOnAlreadyDecided(emit);
    } catch (e, st) {
      log('RewardsBloc: reject failed', error: e, stackTrace: st);
      emit(state.copyWith(isMutating: false, mutationError: _userMessage(e)));
    }
  }

  /// Refreshes the pending queue after a 409 and sets
  /// [RewardsState.redemptionAlreadyDecided] so the dialog can show a toast.
  Future<void> _refreshPendingOnAlreadyDecided(
    Emitter<RewardsState> emit,
  ) async {
    final gymId = _gymId;
    emit(state.copyWith(
      isMutating: false,
      redemptionAlreadyDecided: true,
    ));
    if (gymId == null) return;
    try {
      final items = await _repository.listPending(gymId);
      emit(state.copyWith(
        pendingItems: items,
        pendingStatus: RewardsPendingStatus.loaded,
      ));
    } catch (_) {
      // Silently ignore refresh failure; the already-decided flag is still set.
    }
  }

  String _userMessage(Object e) {
    if (e is ServerException) return e.detail ?? e.message;
    if (e is NetworkException) return e.message;
    return 'Something went wrong. Please try again.';
  }
}
