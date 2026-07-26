import 'dart:developer';

import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:mobile_app/core/errors/exceptions.dart';
import 'package:mobile_app/core/state/selected_member.dart';
import 'package:mobile_app/features/rewards/bloc/rewards_event.dart';
import 'package:mobile_app/features/rewards/bloc/rewards_state.dart';
import 'package:mobile_app/features/rewards/data/models/redemption_record.dart';
import 'package:mobile_app/features/rewards/data/repositories/member_rewards_repository.dart';

/// Drives the rewards surface: loads the gym's ACTIVE catalog and the member's
/// redemption history together, and requests a redemption.
///
/// The points BALANCE is deliberately NOT owned here — it lives on the shared
/// MemberProfileBloc. A successful redeem bumps [RewardsState.redeemSuccessToken]
/// and the screen, on that bump, fires `MemberProfileRefreshRequested` so the
/// balance (+ pending list) refresh from the profile source. Insufficient
/// points is prevented at the UI (the redeem button is disabled when the cost
/// exceeds the balance) AND handled here if the backend still 4xx's.
class RewardsBloc extends Bloc<RewardsEvent, RewardsState> {
  final MemberRewardsRepository _repository;

  RewardsBloc({required MemberRewardsRepository repository})
      : _repository = repository,
        super(const RewardsState()) {
    on<RewardsLoadRequested>(_onLoadRequested);
    on<RewardsRefreshRequested>(_onRefreshRequested);
    on<RewardsRedeemRequested>(_onRedeemRequested);
  }

  String? get _memberId => selectedMember.memberId;
  String? get _gymId => selectedMember.gymId;

  Future<void> _onLoadRequested(
    RewardsLoadRequested event,
    Emitter<RewardsState> emit,
  ) async {
    final gymId = _gymId;
    final memberId = _memberId;
    if (gymId == null || memberId == null) return;

    emit(state.copyWith(status: RewardsStatus.loading, clearError: true));
    await _fetch(gymId: gymId, memberId: memberId, emit: emit);
  }

  /// Pull-to-refresh: the same fetch as a load, minus the flip to `loading`
  /// that would blank the grids under the spinner. Completes `event.done` in a
  /// `finally` so the pull awaits the real fetch.
  Future<void> _onRefreshRequested(
    RewardsRefreshRequested event,
    Emitter<RewardsState> emit,
  ) async {
    try {
      final gymId = _gymId;
      final memberId = _memberId;
      if (gymId == null || memberId == null) return;

      await _fetch(
        gymId: gymId,
        memberId: memberId,
        emit: emit,
        // Only content already on screen is worth protecting; with nothing
        // loaded, the error state is the honest outcome.
        keepContent: state.status == RewardsStatus.loaded,
      );
    } finally {
      event.done?.complete();
    }
  }

  /// Fetch the catalog + redemptions and emit the loaded state. When
  /// [keepContent] is true a catalog failure keeps whatever is on screen
  /// instead of flipping to the error state.
  Future<void> _fetch({
    required String gymId,
    required String memberId,
    required Emitter<RewardsState> emit,
    bool keepContent = false,
  }) async {
    try {
      final catalog =
          await _repository.listCatalog(gymId: gymId, memberId: memberId);
      // Redemptions are best-effort: a failure still shows the catalog.
      List<RedemptionRecord> redemptions;
      try {
        redemptions = await _repository.listRedemptions(
          gymId: gymId,
          memberId: memberId,
        );
      } catch (e, st) {
        log('RewardsBloc: redemptions fetch failed (degrading)',
            error: e, stackTrace: st);
        redemptions = const [];
      }
      emit(state.copyWith(
        status: RewardsStatus.loaded,
        catalog: catalog,
        redemptions: redemptions,
        clearError: true,
      ));
    } catch (e, st) {
      log('RewardsBloc: load failed', error: e, stackTrace: st);
      if (keepContent) return;
      emit(state.copyWith(
        status: RewardsStatus.error,
        errorMessage: _userMessage(e),
      ));
    }
  }

  Future<void> _onRedeemRequested(
    RewardsRedeemRequested event,
    Emitter<RewardsState> emit,
  ) async {
    if (state.isRedeeming) return;
    final gymId = _gymId;
    final memberId = _memberId;
    if (gymId == null || memberId == null) return;

    emit(state.copyWith(isRedeeming: true, clearRedeemError: true));
    try {
      await _repository.redeem(
        gymId: gymId,
        memberId: memberId,
        rewardId: event.rewardId,
      );
      emit(state.copyWith(
        isRedeeming: false,
        redeemSuccessToken: state.redeemSuccessToken + 1,
        clearRedeemError: true,
      ));
    } on ServerException catch (e) {
      // Insufficient points / inactive reward — surface the detail, no crash.
      emit(state.copyWith(
        isRedeeming: false,
        redeemError:
            e.detail ?? 'Could not redeem this reward. Please try again.',
      ));
    } catch (e, st) {
      log('RewardsBloc: redeem failed', error: e, stackTrace: st);
      emit(state.copyWith(
        isRedeeming: false,
        redeemError: _networkMessage(e),
      ));
    }
  }

  String _userMessage(Object e) {
    if (e is ServerException) return e.detail ?? e.message;
    if (e is NetworkException) return e.message;
    return 'Something went wrong. Please try again.';
  }

  String _networkMessage(Object e) {
    if (e is NetworkException) return e.message;
    return 'Something went wrong. Please try again.';
  }
}
