import 'dart:developer';

import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:mobile_app/core/errors/exceptions.dart';
import 'package:mobile_app/core/state/selected_member.dart';
import 'package:mobile_app/features/videos/bloc/videos_event.dart';
import 'package:mobile_app/features/videos/bloc/videos_state.dart';
import 'package:mobile_app/features/videos/data/gym_video_selectors.dart';
import 'package:mobile_app/features/videos/data/models/video_genre.dart';
import 'package:mobile_app/features/videos/data/repositories/member_videos_repository.dart';

/// Drives the videos tab: loads the member's personalized feed from the portal
/// and reloads it per genre when a category tab is selected.
///
/// The "All" load derives the category tab strip from the feed; a genre tab
/// then reloads the feed filtered server-side via `video_type` while the strip
/// stays put. The tag "view all" screen reuses the same bloc with a single
/// `VideosCategorySelected(genre)` (no "All" load, so no tabs).
class VideosBloc extends Bloc<VideosEvent, VideosState> {
  final MemberVideosRepository _repository;

  VideosBloc({required MemberVideosRepository repository})
      : _repository = repository,
        super(const VideosState()) {
    on<VideosLoadRequested>(_onLoadRequested);
    on<VideosCategorySelected>(_onCategorySelected);
  }

  String? get _memberId => selectedMember.memberId;
  String? get _gymId => selectedMember.gymId;

  Future<void> _onLoadRequested(
    VideosLoadRequested event,
    Emitter<VideosState> emit,
  ) async {
    await _load(null, emit, deriveTabs: true);
    // A deep link may open straight to a category: load it after the "All" feed
    // seeded the tab strip, in this same (sequential) handler.
    final initial = event.initialGenre;
    if (initial != null &&
        initial != VideoGenre.unknown &&
        state.status == VideosStatus.loaded) {
      await _load(initial, emit, deriveTabs: false);
    }
  }

  Future<void> _onCategorySelected(
    VideosCategorySelected event,
    Emitter<VideosState> emit,
  ) async {
    // No-op re-tapping the active tab once it has loaded.
    if (state.status == VideosStatus.loaded &&
        event.genre == state.selectedGenre) {
      return;
    }
    // "All" re-derives the tab strip; a genre load keeps the existing strip.
    await _load(event.genre, emit, deriveTabs: event.genre == null);
  }

  Future<void> _load(
    VideoGenre? genre,
    Emitter<VideosState> emit, {
    required bool deriveTabs,
  }) async {
    final gymId = _gymId;
    final memberId = _memberId;
    if (gymId == null || memberId == null) return;

    emit(state.copyWith(
      status: VideosStatus.loading,
      selectedGenre: genre,
      clearSelectedGenre: genre == null,
      clearError: true,
    ));
    try {
      final feed = await _repository.fetchFeed(
        gymId: gymId,
        memberId: memberId,
        videoType: genre,
      );
      emit(state.copyWith(
        status: VideosStatus.loaded,
        videos: feed.videos,
        availableGenres:
            deriveTabs ? genresInFeed(feed.videos) : state.availableGenres,
        clearError: true,
      ));
    } catch (e, st) {
      log('VideosBloc: load failed', error: e, stackTrace: st);
      emit(state.copyWith(
        status: VideosStatus.error,
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
