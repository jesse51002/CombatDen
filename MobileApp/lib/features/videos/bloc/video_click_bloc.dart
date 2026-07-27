import 'dart:developer';

import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:mobile_app/core/state/selected_member.dart';
import 'package:mobile_app/features/videos/bloc/video_click_bloc_state.dart';
import 'package:mobile_app/features/videos/bloc/video_click_event.dart';
import 'package:mobile_app/features/videos/data/repositories/member_videos_repository.dart';

/// Reports every FEED video open to the member portal, so the taste profile
/// learns from the videos the member chose for themselves and not only from
/// the one rotating recommendation the system served.
///
/// It is a pure sink: it holds no data, emits no state, and never throws — the
/// same best-effort posture as [VideoRecBloc]'s click. A failed or slow report
/// can therefore never block, delay, or surface an error over the YouTube
/// launch that runs alongside it.
///
/// App-lifetime and provided once above the router (see `VideoClickScope`), so
/// every existing video surface reports without a per-call-site wiring change.
/// `gymId` / `memberId` come from the [selectedMember] global, as the other
/// member-portal video calls do.
class VideoClickBloc extends Bloc<VideoClickEvent, VideoClickBlocState> {
  final MemberVideosRepository _repository;

  VideoClickBloc({required MemberVideosRepository repository})
      : _repository = repository,
        super(const VideoClickBlocState()) {
    on<VideoOpenedFromFeed>(_onOpened);
  }

  Future<void> _onOpened(
    VideoOpenedFromFeed event,
    Emitter<VideoClickBlocState> emit,
  ) async {
    final gymId = selectedMember.gymId;
    final memberId = selectedMember.memberId;
    final videoId = event.videoId.trim();
    if (gymId == null || memberId == null || videoId.isEmpty) return;
    // Best-effort: swallow every failure. No state change — nothing on screen
    // depends on the report landing.
    try {
      await _repository.recordVideoClick(
        gymId: gymId,
        memberId: memberId,
        videoId: videoId,
      );
    } catch (e, st) {
      log('VideoClickBloc: feed click failed (ignored)',
          error: e, stackTrace: st);
    }
  }
}
