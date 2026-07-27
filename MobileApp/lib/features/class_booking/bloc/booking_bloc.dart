import 'dart:developer';

import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:mobile_app/core/errors/exceptions.dart';
import 'package:mobile_app/core/state/selected_member.dart';
import 'package:mobile_app/features/class_booking/bloc/booking_event.dart';
import 'package:mobile_app/features/class_booking/bloc/booking_state.dart';
import 'package:mobile_app/features/class_booking/data/booking_rejection.dart';
import 'package:mobile_app/features/home/data/models/class_occurrence.dart';
import 'package:mobile_app/features/home/data/repositories/member_class_history_repository.dart';
import 'package:mobile_app/features/home/data/repositories/member_signup_repository.dart';

const String _kReserveFallback =
    'Could not reserve your spot. Please try again.';
const String _kCancelFallback = 'Could not cancel. Please try again.';
const String _kGenericFallback = 'Something went wrong. Please try again.';

/// Reserve / cancel a member's spot on one class occurrence.
///
/// Addresses the occurrence by its ORIGINAL slot
/// `(class_id, original_date, original_time)`, echoed VERBATIM from the board.
/// An idempotent repeat (`already_signed_up`) is treated as a reserve success.
///
/// **A rejection is classified by the backend's `code`, never by its message.**
/// The wire shape is `{"detail": "...", "code": "class_full"}` and the backend
/// treats the exception type as the sole source of truth for the code, so the
/// prose may be reworded at any time. [BookingRejection] owns the
/// code -> member-facing copy mapping; this bloc only resolves it and emits it.
class BookingBloc extends Bloc<BookingEvent, BookingState> {
  final MemberSignupRepository _repository;
  final MemberClassHistoryRepository _historyRepository;
  final ClassOccurrence _occurrence;

  BookingBloc({
    required MemberSignupRepository repository,
    required MemberClassHistoryRepository historyRepository,
    required ClassOccurrence occurrence,
    required bool initiallyBooked,
  })  : _repository = repository,
        _historyRepository = historyRepository,
        _occurrence = occurrence,
        super(BookingState(booked: initiallyBooked)) {
    on<BookingReserveRequested>(_onReserve);
    on<BookingCancelRequested>(_onCancel);
    on<BookingReservationSyncRequested>(_onReservationSync);
  }

  String? get _memberId => selectedMember.memberId;
  String? get _gymId => selectedMember.gymId;

  /// Confirm the seeded `booked` flag against the member's own open
  /// reservations — the same feed the board joins on, read for this member
  /// directly so a wrong (or missing) route argument cannot survive.
  ///
  /// Best-effort by design: a failure keeps the seeded value and surfaces
  /// nothing. The screen's job is the class; a banner about a background
  /// confirmation would be noise, and the reserve call is idempotent anyway.
  Future<void> _onReservationSync(
    BookingReservationSyncRequested event,
    Emitter<BookingState> emit,
  ) async {
    final gymId = _gymId;
    final memberId = _memberId;
    if (gymId == null || memberId == null) return;

    try {
      final history = await _historyRepository.getHistory(
        gymId: gymId,
        memberId: memberId,
      );
      final booked = history.upcoming.any(
        (r) => r.slotKey == _occurrence.slotKey,
      );
      // Only a seed correction: once the member has reserved or cancelled
      // here, THEIR action is the truth and a late read must not undo it.
      if (!state.isUntouched || booked == state.booked) return;
      emit(state.copyWith(booked: booked));
    } catch (e, st) {
      log('BookingBloc: reservation sync failed', error: e, stackTrace: st);
    }
  }

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
      emit(_rejected(e, _kReserveFallback));
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
      // Same treatment as reserve: the cancel route today can only 200 or
      // fail generically, but it shares the rejection path, so classifying by
      // code costs nothing and is already right if a typed rejection is ever
      // added to it.
      emit(_rejected(e, _kCancelFallback));
    } catch (e, st) {
      log('BookingBloc: cancel failed', error: e, stackTrace: st);
      emit(state.copyWith(
        status: BookingStatus.error,
        errorMessage: _networkMessage(e),
      ));
    }
  }

  /// Classify a backend refusal by its `code` and pick the copy: our own
  /// member-facing wording for a code we know, else the backend's `detail`,
  /// else [fallback]. Never blank.
  BookingState _rejected(ServerException e, String fallback) {
    final rejection = BookingRejection.fromCode(e.code);
    return state.copyWith(
      status: BookingStatus.error,
      rejection: rejection,
      errorMessage: rejection.memberMessage ?? e.detail ?? fallback,
    );
  }

  String _networkMessage(Object e) {
    if (e is NetworkException) return e.message;
    return _kGenericFallback;
  }
}
