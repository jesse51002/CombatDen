import 'dart:developer';

import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:mobile_app/core/errors/exceptions.dart';
import 'package:mobile_app/core/state/selected_member.dart';
import 'package:mobile_app/features/profile/bloc/member_profile_event.dart';
import 'package:mobile_app/features/profile/bloc/member_profile_state.dart';
import 'package:mobile_app/features/profile/data/repositories/member_profile_repository.dart';

/// The app-wide member-profile source.
///
/// Provided ONCE above the app shell's nested navigator, so the topbar and
/// later features read the SAME retention / rank / membership data. Reset +
/// reloaded on a member switch (the shell re-keys its subtree on the selected
/// member id, recreating this bloc), refreshed on reserve / cancel (and — later
/// — redeem / celebration) via [MemberProfileRefreshRequested], and on app
/// foreground.
class MemberProfileBloc extends Bloc<MemberProfileEvent, MemberProfileState> {
  final MemberProfileRepository _repository;

  MemberProfileBloc({required MemberProfileRepository repository})
      : _repository = repository,
        super(const MemberProfileState()) {
    on<MemberProfileLoadRequested>(_onLoadRequested);
    on<MemberProfileRefreshRequested>(_onRefreshRequested);
  }

  String? get _memberId => selectedMember.memberId;
  String? get _gymId => selectedMember.gymId;

  Future<void> _onLoadRequested(
    MemberProfileLoadRequested event,
    Emitter<MemberProfileState> emit,
  ) async {
    final memberId = _memberId;
    final gymId = _gymId;
    if (memberId == null || gymId == null) return;

    emit(state.copyWith(
      status: MemberProfileStatus.loading,
      clearError: true,
    ));
    try {
      final profile =
          await _repository.getProfile(gymId: gymId, memberId: memberId);
      emit(state.copyWith(
        status: MemberProfileStatus.loaded,
        profile: profile,
        clearError: true,
      ));
    } catch (e, st) {
      log('MemberProfileBloc: load failed', error: e, stackTrace: st);
      emit(state.copyWith(
        status: MemberProfileStatus.error,
        errorMessage: _userMessage(e),
      ));
    }
  }

  /// Silent re-fetch: never flips to a loading/error state that would blank a
  /// profile already on screen. A failure keeps the last-good data.
  Future<void> _onRefreshRequested(
    MemberProfileRefreshRequested event,
    Emitter<MemberProfileState> emit,
  ) async {
    final memberId = _memberId;
    final gymId = _gymId;
    if (memberId == null || gymId == null) return;

    try {
      final profile =
          await _repository.getProfile(gymId: gymId, memberId: memberId);
      emit(state.copyWith(
        status: MemberProfileStatus.loaded,
        profile: profile,
        clearError: true,
      ));
    } catch (e, st) {
      // Background refresh — keep the last-good profile, don't clobber the UI.
      log('MemberProfileBloc: refresh failed', error: e, stackTrace: st);
    }
  }

  String _userMessage(Object e) {
    if (e is ServerException) return e.detail ?? e.message;
    if (e is NetworkException) return e.message;
    return 'Something went wrong. Please try again.';
  }
}
