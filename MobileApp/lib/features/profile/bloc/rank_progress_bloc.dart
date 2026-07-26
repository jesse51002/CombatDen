import 'dart:developer';

import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:mobile_app/core/errors/exceptions.dart';
import 'package:mobile_app/core/state/selected_member.dart';
import 'package:mobile_app/features/profile/bloc/rank_progress_event.dart';
import 'package:mobile_app/features/profile/bloc/rank_progress_state.dart';
import 'package:mobile_app/features/profile/data/repositories/member_rank_progress_repository.dart';

/// Drives the profile's rank-progress graph: loads the member's
/// classes-into-rank series (a sawtooth resetting to 0 at each promotion and
/// climbing toward the per-step threshold) from the portal. Scoped to the
/// selected member; a load with no rank / no history comes back as an empty
/// (but loaded) series the graph renders as its empty state.
class RankProgressBloc extends Bloc<RankProgressEvent, RankProgressState> {
  final MemberRankProgressRepository _repository;

  RankProgressBloc({required MemberRankProgressRepository repository})
      : _repository = repository,
        super(const RankProgressState()) {
    on<RankProgressLoadRequested>(_onLoadRequested);
    on<RankProgressRefreshRequested>(_onRefreshRequested);
  }

  String? get _memberId => selectedMember.memberId;
  String? get _gymId => selectedMember.gymId;

  Future<void> _onLoadRequested(
    RankProgressLoadRequested event,
    Emitter<RankProgressState> emit,
  ) async {
    final gymId = _gymId;
    final memberId = _memberId;
    if (gymId == null || memberId == null) return;

    emit(state.copyWith(
      status: RankProgressStatus.loading,
      clearError: true,
    ));
    await _fetch(gymId: gymId, memberId: memberId, emit: emit);
  }

  /// Pull-to-refresh: the same fetch, minus the flip to `loading` that would
  /// blank the graph under the spinner. Completes `event.done` in a `finally`
  /// so the pull awaits the real fetch.
  Future<void> _onRefreshRequested(
    RankProgressRefreshRequested event,
    Emitter<RankProgressState> emit,
  ) async {
    try {
      final gymId = _gymId;
      final memberId = _memberId;
      if (gymId == null || memberId == null) return;

      await _fetch(
        gymId: gymId,
        memberId: memberId,
        emit: emit,
        keepContent: state.status == RankProgressStatus.loaded,
      );
    } finally {
      event.done?.complete();
    }
  }

  /// Fetch the series and emit it. When [keepContent] is true a failure keeps
  /// the drawn graph instead of flipping to the error state.
  Future<void> _fetch({
    required String gymId,
    required String memberId,
    required Emitter<RankProgressState> emit,
    bool keepContent = false,
  }) async {
    try {
      final progress =
          await _repository.getRankProgress(gymId: gymId, memberId: memberId);
      emit(state.copyWith(
        status: RankProgressStatus.loaded,
        points: progress.points,
        clearError: true,
      ));
    } catch (e, st) {
      log('RankProgressBloc: load failed', error: e, stackTrace: st);
      if (keepContent) return;
      emit(state.copyWith(
        status: RankProgressStatus.error,
        errorMessage: _userMessage(e),
      ));
    }
  }

  String _userMessage(Object e) {
    if (e is ServerException) return e.detail ?? e.message;
    if (e is NetworkException) return e.message;
    return 'Something went wrong. Please try again.';
  }
}
