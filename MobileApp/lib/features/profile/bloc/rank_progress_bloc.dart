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
