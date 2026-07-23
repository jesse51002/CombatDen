import 'dart:developer';

import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:mobile_app/core/errors/exceptions.dart';
import 'package:mobile_app/core/state/selected_member.dart';
import 'package:mobile_app/features/class_booking/bloc/booking_event.dart';
import 'package:mobile_app/features/class_booking/bloc/booking_state.dart';
import 'package:mobile_app/features/home/data/models/class_occurrence.dart';
import 'package:mobile_app/features/home/data/repositories/member_signup_repository.dart';

/// Reserve / cancel a member's spot on one class occurrence.
///
/// Addresses the occurrence by its ORIGINAL slot
/// `(class_id, original_date, original_time)`, echoed VERBATIM from the board.
/// An idempotent repeat (`already_signed_up`) is treated as a reserve success;
/// a full class is surfaced as a distinct [BookingState.fullClass] error, other
/// 4xx as the backend's `detail`.
class BookingBloc extends Bloc<BookingEvent, BookingState> {
  final MemberSignupRepository _repository;
  final ClassOccurrence _occurrence;

  BookingBloc({
    required MemberSignupRepository repository,
    required ClassOccurrence occurrence,
    required bool initiallyBooked,
  })  : _repository = repository,
        _occurrence = occurrence,
        super(BookingState(booked: initiallyBooked)) {
    on<BookingReserveRequested>(_onReserve);
    on<BookingCancelRequested>(_onCancel);
  }

  String? get _memberId => selectedMember.memberId;
  String? get _gymId => selectedMember.gymId;

  Future<void> _onReserve(
    BookingReserveRequested event,
    Emitter<BookingState> emit,
  ) async {
    if (state.isBusy) return;
    final gymId = _gymId;
    final memberId = _memberId;
    if (gymId == null || memberId == null) return;

    emit(state.copyWith(
      status: BookingStatus.reserving,
      fullClass: false,
      clearError: true,
    ));
    try {
      // already_signed_up=true is still a 200 — treated as success.
      await _repository.reserve(
        gymId: gymId,
        memberId: memberId,
        classId: _occurrence.classId,
        occurrenceDate: _occurrence.originalDate,
        occurrenceTime: _occurrence.originalTime,
      );
      emit(state.copyWith(
        booked: true,
        status: BookingStatus.idle,
        reserveSuccessToken: state.reserveSuccessToken + 1,
        clearError: true,
      ));
    } on ServerException catch (e) {
      final detail = e.detail;
      final isFull = detail != null && detail.toLowerCase().contains('full');
      emit(state.copyWith(
        status: BookingStatus.error,
        fullClass: isFull,
        errorMessage: isFull
            ? 'Class is full'
            : (detail ?? 'Could not reserve your spot. Please try again.'),
      ));
    } catch (e, st) {
      log('BookingBloc: reserve failed', error: e, stackTrace: st);
      emit(state.copyWith(
        status: BookingStatus.error,
        errorMessage: _networkMessage(e),
      ));
    }
  }

  Future<void> _onCancel(
    BookingCancelRequested event,
    Emitter<BookingState> emit,
  ) async {
    if (state.isBusy) return;
    final gymId = _gymId;
    final memberId = _memberId;
    if (gymId == null || memberId == null) return;

    emit(state.copyWith(
      status: BookingStatus.cancelling,
      fullClass: false,
      clearError: true,
    ));
    try {
      // removed=false (no reservation) is still a 200 — the end state is the
      // same: the member is not booked. Confirm either way.
      await _repository.cancel(
        gymId: gymId,
        memberId: memberId,
        classId: _occurrence.classId,
        occurrenceDate: _occurrence.originalDate,
        occurrenceTime: _occurrence.originalTime,
      );
      emit(state.copyWith(
        booked: false,
        status: BookingStatus.idle,
        cancelSuccessToken: state.cancelSuccessToken + 1,
        clearError: true,
      ));
    } on ServerException catch (e) {
      emit(state.copyWith(
        status: BookingStatus.error,
        errorMessage: e.detail ?? 'Could not cancel. Please try again.',
      ));
    } catch (e, st) {
      log('BookingBloc: cancel failed', error: e, stackTrace: st);
      emit(state.copyWith(
        status: BookingStatus.error,
        errorMessage: _networkMessage(e),
      ));
    }
  }

  String _networkMessage(Object e) {
    if (e is NetworkException) return e.message;
    return 'Something went wrong. Please try again.';
  }
}
