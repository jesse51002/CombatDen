import 'dart:developer';

import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/errors/exceptions.dart';
import 'package:crm/features/members/data/video_config_repository.dart';
import 'package:crm/features/video_config/bloc/video_config_event.dart';
import 'package:crm/features/video_config/bloc/video_config_state.dart';
import 'package:crm/features/video_config/data/models/video_config_models.dart';

/// Bloc for the video-config agent screen.
///
/// Manages the on-open refine + load sequence, the in-session chat
/// (history round-tripping with the stateless backend), the draft-review
/// confirm/dismiss flow, and the save operation.
class VideoConfigBloc
    extends Bloc<VideoConfigEvent, VideoConfigState> {
  final VideoConfigRepository _repository;
  String _gymId = '';

  VideoConfigBloc({required VideoConfigRepository repository})
      : _repository = repository,
        super(const VideoConfigState()) {
    on<VideoConfigScreenOpened>(_onScreenOpened);
    on<VideoConfigMessageSent>(_onMessageSent);
    on<VideoConfigDraftConfirmed>(_onDraftConfirmed);
    on<VideoConfigDraftDismissed>(
      (_, emit) => emit(state.copyWith(clearPendingDraft: true)),
    );
    on<VideoConfigErrorCleared>(
      (_, emit) => emit(state.copyWith(clearError: true)),
    );
  }

  // ── On open ──────────────────────────────────────────────────────────────

  Future<void> _onScreenOpened(
    VideoConfigScreenOpened event,
    Emitter<VideoConfigState> emit,
  ) async {
    _gymId = event.gymId;

    // Step 1 — refine from feed (shows a brief "Improving…" banner).
    emit(
      state.copyWith(
        loadStatus: VideoConfigLoadStatus.refining,
        clearError: true,
      ),
    );

    VideoConfigView? refined;
    try {
      refined = await _repository.refineFromFeed(_gymId);
    } catch (e, st) {
      // Non-fatal: log and continue to getConfig.
      log('VideoConfigBloc: refineFromFeed error (continuing)', error: e, stackTrace: st);
    }

    // Step 2 — if refine returned a config, use it directly;
    // otherwise fall through to getConfig.
    if (refined != null) {
      emit(
        state.copyWith(
          loadStatus: VideoConfigLoadStatus.loaded,
          savedConfig: refined,
        ),
      );
      return;
    }

    // Step 3 — load current config.
    emit(state.copyWith(loadStatus: VideoConfigLoadStatus.loading));
    try {
      final config = await _repository.getConfig(_gymId);
      emit(
        state.copyWith(
          loadStatus: config != null
              ? VideoConfigLoadStatus.loaded
              : VideoConfigLoadStatus.empty,
          savedConfig: config,
        ),
      );
    } catch (e, st) {
      log('VideoConfigBloc: getConfig failed', error: e, stackTrace: st);
      emit(
        state.copyWith(
          loadStatus: VideoConfigLoadStatus.error,
          error: _userMessage(e),
        ),
      );
    }
  }

  // ── Chat ─────────────────────────────────────────────────────────────────

  Future<void> _onMessageSent(
    VideoConfigMessageSent event,
    Emitter<VideoConfigState> emit,
  ) async {
    final userMsg = ChatMessage(text: event.text, isUser: true);
    final updatedMessages = [...state.messages, userMsg];

    emit(
      state.copyWith(
        messages: updatedMessages,
        chatStatus: VideoConfigChatStatus.typing,
        clearPendingDraft: true,    // clear prior draft on new turn
        saveStatus: VideoConfigSaveStatus.idle,
        clearError: true,
      ),
    );

    try {
      final result = await _repository.agentTurn(
        _gymId,
        event.text,
        history: state.agentHistory,
      );

      final withReply = result.reply != null
          ? [
              ...updatedMessages,
              ChatMessage(text: result.reply!, isUser: false),
            ]
          : updatedMessages;

      emit(
        state.copyWith(
          messages: withReply,
          agentHistory: result.history,
          chatStatus: VideoConfigChatStatus.idle,
          pendingDraft: result.draft,
        ),
      );
    } catch (e, st) {
      log('VideoConfigBloc: agentTurn failed', error: e, stackTrace: st);
      emit(
        state.copyWith(
          chatStatus: VideoConfigChatStatus.idle,
          error: _userMessage(e),
        ),
      );
    }
  }

  // ── Draft confirm ─────────────────────────────────────────────────────────

  Future<void> _onDraftConfirmed(
    VideoConfigDraftConfirmed event,
    Emitter<VideoConfigState> emit,
  ) async {
    final draft = state.pendingDraft;
    if (draft == null || state.saveStatus == VideoConfigSaveStatus.saving) {
      return;
    }

    emit(
      state.copyWith(
        saveStatus: VideoConfigSaveStatus.saving,
        clearError: true,
      ),
    );

    try {
      final saved = await _repository.saveConfig(_gymId, draft);
      emit(
        state.copyWith(
          savedConfig: saved,
          loadStatus: VideoConfigLoadStatus.loaded,
          clearPendingDraft: true,
          saveStatus: VideoConfigSaveStatus.saved,
        ),
      );
    } catch (e, st) {
      log('VideoConfigBloc: saveConfig failed', error: e, stackTrace: st);
      emit(
        state.copyWith(
          saveStatus: VideoConfigSaveStatus.error,
          error: _userMessage(e),
        ),
      );
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _userMessage(Object e) {
    if (e is ServerException) return e.detail ?? e.message;
    if (e is NetworkException) return e.message;
    return 'Something went wrong. Please try again.';
  }
}
