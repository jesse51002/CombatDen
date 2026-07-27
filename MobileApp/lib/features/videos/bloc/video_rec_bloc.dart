import 'dart:developer';

import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:mobile_app/core/errors/exceptions.dart';
import 'package:mobile_app/core/state/selected_member.dart';
import 'package:mobile_app/features/videos/bloc/video_rec_event.dart';
import 'package:mobile_app/features/videos/bloc/video_rec_state.dart';
import 'package:mobile_app/features/videos/data/repositories/member_videos_repository.dart';

/// Drives the single video-recommendation surface: loads the member's next
/// rotating-category rec and records a click when it's opened.
///
/// A 404 (no rec available) is an [VideoRecStatus.empty] state, not an error —
/// the post-booking flow must never be trapped. The click is best-effort: it is
/// awaited only to catch+log failures, never emits, and never throws, so
/// closing the screen is instant and unaffected.
class VideoRecBloc extends Bloc<VideoRecEvent, VideoRecState> {
  final MemberVideosRepository _repository;

  VideoRecBloc({required MemberVideosRepository repository})
      : _repository = repository,
        super(const VideoRecState()) {
    on<VideoRecRequested>(_onRequested);
    on<VideoRecOpened>(_onOpened);
  }

  String? get _memberId => selectedMember.memberId;
  String? get _gymId => selectedMember.gymId;

  Future<void> _onRequested(
    VideoRecRequested event,
    Emitter<VideoRecState> emit,
  ) async {
    final gymId = _gymId;
    final memberId = _memberId;
    if (gymId == null || memberId == null) {
      emit(state.copyWith(status: VideoRecStatus.empty));
      return;
    }

    emit(state.copyWith(status: VideoRecStatus.loading, clearError: true));
    try {
      final rec = await _repository.fetchRec(gymId: gymId, memberId: memberId);
      emit(state.copyWith(status: VideoRecStatus.loaded, rec: rec));
    } on ServerException catch (e) {
      // 404 = no category yields a video: a legitimate empty state.
      if (e.statusCode == 404) {
        emit(state.copyWith(status: VideoRecStatus.empty));
        return;
      }
      emit(state.copyWith(
        status: VideoRecStatus.error,
        errorMessage: e.detail ?? e.message,
      ));
    } catch (e, st) {
      log('VideoRecBloc: load failed', error: e, stackTrace: st);
      emit(state.copyWith(
        status: VideoRecStatus.error,
        errorMessage: _networkMessage(e),
      ));
    }
  }

  Future<void> _onOpened(
    VideoRecOpened event,
    Emitter<VideoRecState> emit,
  ) async {
    final rec = state.rec;
    final gymId = _gymId;
    final memberId = _memberId;
    if (rec == null || gymId == null || memberId == null) return;
    // Best-effort: swallow every failure so navigation is never blocked. No
    // state change — the screen closes regardless of the click's outcome.
    try {
      await _repository.recordRecClick(
        gymId: gymId,
        memberId: memberId,
        recId: rec.recId,
      );
    } catch (e, st) {
      log('VideoRecBloc: rec click failed (ignored)', error: e, stackTrace: st);
    }
  }

  String _networkMessage(Object e) {
    if (e is NetworkException) return e.message;
    return 'Something went wrong. Please try again.';
  }
}
