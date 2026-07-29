import 'dart:developer';

import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:mobile_app/core/errors/exceptions.dart';
import 'package:mobile_app/core/state/selected_member.dart';
import 'package:mobile_app/features/home/data/models/class_occurrence.dart';
import 'package:mobile_app/features/home/data/repositories/member_classes_repository.dart';
import 'package:mobile_app/features/home/data/schedule_dates.dart';
import 'package:mobile_app/features/qr_checkin/bloc/checkin_pick_class_event.dart';
import 'package:mobile_app/features/qr_checkin/bloc/checkin_pick_class_state.dart';

/// Loads today's class occurrences so the member can pick which one they're
/// checking into. It reuses the home board read
/// ([MemberClassesRepository.getBoard]) over a today→today (gym-local) window,
/// drops cancelled occurrences, and sorts soonest-first.
///
/// A fetch failure is a retry-able error; a successful fetch with no classes
/// is the empty state, NOT an error.
class CheckinPickClassBloc
    extends Bloc<CheckinPickClassEvent, CheckinPickClassState> {
  final MemberClassesRepository _classesRepository;

  CheckinPickClassBloc({required MemberClassesRepository classesRepository})
      : _classesRepository = classesRepository,
        super(const CheckinPickClassState()) {
    on<CheckinPickClassLoadRequested>(_onLoadRequested);
  }

  Future<void> _onLoadRequested(
    CheckinPickClassLoadRequested event,
    Emitter<CheckinPickClassState> emit,
  ) async {
    final gymId = selectedMember.gymId;
    final memberId = selectedMember.memberId;
    if (gymId == null || memberId == null) {
      emit(state.copyWith(
        status: CheckinPickClassStatus.error,
        errorMessage: 'No member is selected. Switch profile and try again.',
      ));
      return;
    }

    emit(state.copyWith(
      status: CheckinPickClassStatus.loading,
      clearError: true,
    ));

    final today = isoDate(todayLocal());
    final List<ClassOccurrence> board;
    try {
      board = await _classesRepository.getBoard(
        gymId: gymId,
        memberId: memberId,
        startDate: today,
        endDate: today,
      );
    } catch (e, st) {
      log('CheckinPickClassBloc: board fetch failed', error: e, stackTrace: st);
      emit(state.copyWith(
        status: CheckinPickClassStatus.error,
        errorMessage: _userMessage(e),
      ));
      return;
    }

    final pickable = [
      for (final o in board)
        if (!o.isCancelled) o,
    ]..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));

    emit(state.copyWith(
      status: CheckinPickClassStatus.loaded,
      occurrences: pickable,
      clearError: true,
    ));
  }

  String _userMessage(Object e) {
    if (e is ServerException) return e.detail ?? e.message;
    if (e is NetworkException) return e.message;
    return 'Something went wrong. Please try again.';
  }
}
