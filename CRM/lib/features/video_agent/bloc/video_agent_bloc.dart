import 'dart:developer';

import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/errors/exceptions.dart';
import 'package:crm/features/members/data/video_agent_repository.dart';
import 'package:crm/features/video_agent/bloc/video_agent_event.dart';
import 'package:crm/features/video_agent/bloc/video_agent_state.dart';
import 'package:crm/features/video_agent/data/models/video_agent_models.dart';

/// Deterministic opening message for a brand-new gym (no spec yet) — a request
/// that starts the conversation. Shown instantly, no LLM call.
const String _kCreateFirstMessage =
    "Let's set up your video feed. Tell me about your gym — what disciplines "
    'do you teach, who are your members, and what kind of videos would they '
    'love to see?';

/// Deterministic opening when a spec already exists (edit) — a multi-select
/// request rendered as chips. The owner picks what to change and the selection
/// becomes the first message to the agent. Shown instantly, no LLM call.
const AgentQuestion _kEditQuestion = AgentQuestion(
  question: 'Welcome back — your current feed criteria are on the right. '
      'What would you like to change?',
  options: [
    'Add to what we surface',
    'Cut something we show',
    'Adjust what we avoid',
    'Change the disciplines',
    'Refresh the vibe',
  ],
  multiSelect: true,
);

/// Bloc for the video-agent screen.
///
/// Manages the on-open refine + load sequence, the in-session chat
/// (history round-tripping with the stateless backend), the draft-review
/// confirm/dismiss flow, and the multi-choice question surface.
///
/// Accept path: [VideoAgentDraftConfirmed] → agent turn with `accepted_spec`
/// → on `saved == true`: append reply + clear draft + mark saved, chat stays
/// open. No `saveConfig` / `generateQueries` calls.
class VideoAgentBloc
    extends Bloc<VideoAgentEvent, VideoAgentState> {
  final VideoAgentRepository _repository;
  String _gymId = '';

  VideoAgentBloc({required VideoAgentRepository repository})
      : _repository = repository,
        super(const VideoAgentState()) {
    on<VideoAgentScreenOpened>(_onScreenOpened);
    on<VideoAgentMessageSent>(_onMessageSent);
    on<VideoAgentDraftConfirmed>(_onDraftConfirmed);
    on<VideoAgentDraftDismissed>(_onDraftDismissed);
    on<VideoAgentErrorCleared>(
      (_, emit) => emit(state.copyWith(clearError: true)),
    );
  }

  // ── On open ──────────────────────────────────────────────────────────────

  Future<void> _onScreenOpened(
    VideoAgentScreenOpened event,
    Emitter<VideoAgentState> emit,
  ) async {
    _gymId = event.gymId;

    // Step 1 — refine from feed (shows a brief "Improving…" banner).
    emit(
      state.copyWith(
        loadStatus: VideoAgentLoadStatus.refining,
        clearError: true,
      ),
    );

    VideoSpecView? refined;
    try {
      refined = await _repository.refineFromFeed(_gymId);
    } catch (e, st) {
      // Non-fatal: log and continue to getConfig.
      log(
        'VideoAgentBloc: refineFromFeed error (continuing)',
        error: e,
        stackTrace: st,
      );
    }

    // Step 2 — if refine returned a spec, use it directly; otherwise load
    // the current spec.
    if (refined != null) {
      emit(
        state.copyWith(
          loadStatus: VideoAgentLoadStatus.loaded,
          savedConfig: refined,
        ),
      );
    } else {
      emit(state.copyWith(loadStatus: VideoAgentLoadStatus.loading));
      try {
        final config = await _repository.getConfig(_gymId);
        emit(
          state.copyWith(
            loadStatus: config != null
                ? VideoAgentLoadStatus.loaded
                : VideoAgentLoadStatus.empty,
            savedConfig: config,
          ),
        );
      } catch (e, st) {
        log('VideoAgentBloc: getConfig failed', error: e, stackTrace: st);
        emit(
          state.copyWith(
            loadStatus: VideoAgentLoadStatus.error,
            error: _userMessage(e),
          ),
        );
        return;
      }
    }

    // Step 3 — seed a deterministic first turn so the chat is never empty.
    // No LLM call (instant, works without a key): a brand-new gym (create) gets
    // a plain text request; an existing spec (edit) gets a multi-select
    // question. The real agent conversation begins when the owner replies.
    _seedFirstTurn(emit);
  }

  /// Seeds the agent's deterministic opening — a request that kicks off the
  /// conversation. **Create** (no spec yet): a plain text message. **Edit** (a
  /// spec already exists): a multi-select [AgentQuestion] rendered as chips.
  /// Purely client-side: no backend/LLM call, so it shows instantly and needs
  /// no API key.
  void _seedFirstTurn(Emitter<VideoAgentState> emit) {
    if (state.savedConfig != null) {
      emit(state.copyWith(pendingQuestion: _kEditQuestion));
    } else {
      emit(
        state.copyWith(
          messages: [
            ...state.messages,
            ChatMessage(text: _kCreateFirstMessage, isUser: false),
          ],
        ),
      );
    }
  }

  // ── Chat ─────────────────────────────────────────────────────────────────

  Future<void> _onMessageSent(
    VideoAgentMessageSent event,
    Emitter<VideoAgentState> emit,
  ) async {
    final pending = state.pendingQuestion;
    // If a question was pending, record it as the agent's bubble before the
    // owner's answer, and carry the option list + selection onto the answer so
    // it renders as the read-only highlighted-options widget (or, for a typed
    // reply, none-selected with the text below). An answered question becomes
    // part of the chat history, not just the transient chip card.
    final updatedMessages = [
      ...state.messages,
      if (pending != null)
        ChatMessage(text: pending.question, isUser: false),
      ChatMessage(
        text: event.text,
        isUser: true,
        options: pending?.options,
        selectedOptions: event.selectedOptions ?? const [],
      ),
    ];

    emit(
      state.copyWith(
        messages: updatedMessages,
        chatStatus: VideoAgentChatStatus.typing,
        clearPendingDraft: true,
        clearPendingQuestion: true,
        saveStatus: VideoAgentSaveStatus.idle,
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
          chatStatus: VideoAgentChatStatus.idle,
          pendingDraft: result.draft,
          clearPendingQuestion: result.question == null,
          pendingQuestion: result.question,
        ),
      );
    } catch (e, st) {
      log('VideoAgentBloc: agentTurn failed', error: e, stackTrace: st);
      emit(
        state.copyWith(
          chatStatus: VideoAgentChatStatus.idle,
          messages: [
            ...state.messages,
            ChatMessage(
              text: _userMessage(e),
              isUser: false,
              status: ChatMessageStatus.error,
            ),
          ],
        ),
      );
    }
  }

  // ── Draft confirm ─────────────────────────────────────────────────────────

  /// Sends the draft back to the agent as `accepted_spec` so the backend
  /// can persist it. On `saved == true`: appends the agent's acknowledgement
  /// reply, clears the pending draft, marks [VideoAgentSaveStatus.saved], and
  /// keeps the chat open — the owner may continue chatting.
  Future<void> _onDraftConfirmed(
    VideoAgentDraftConfirmed event,
    Emitter<VideoAgentState> emit,
  ) async {
    final draft = state.pendingDraft;
    if (draft == null || state.saveStatus == VideoAgentSaveStatus.saving) {
      return;
    }

    emit(
      state.copyWith(
        saveStatus: VideoAgentSaveStatus.saving,
        clearError: true,
      ),
    );

    try {
      final result = await _repository.agentTurn(
        _gymId,
        'Confirm and save this spec.',
        history: state.agentHistory,
        acceptedSpec: draft.toJson(),
      );

      if (result.saved) {
        // Build a local VideoSpecView from the confirmed criteria (no extra
        // network call required; queries are server-side and never shown).
        final savedSpec = VideoSpecView(
          gymId: _gymId,
          disciplines: draft.disciplines,
          videosDesc: draft.videosDesc,
          avoidDesc: draft.avoidDesc,
          shortVideosDesc: draft.shortVideosDesc,
          shortAvoidDesc: draft.shortAvoidDesc,
          queries: const [],
          source: 'agent',
        );
        emit(
          state.copyWith(
            // Green outcome card marks the save, then the agent's reply.
            messages: [
              ...state.messages,
              const ChatMessage(
                text: 'Spec saved.',
                isUser: false,
                status: ChatMessageStatus.saved,
              ),
              if (result.reply != null)
                ChatMessage(text: result.reply!, isUser: false),
            ],
            agentHistory: result.history,
            chatStatus: VideoAgentChatStatus.idle,
            savedConfig: savedSpec,
            loadStatus: VideoAgentLoadStatus.loaded,
            clearPendingDraft: true,
            clearPendingQuestion: result.question == null,
            pendingQuestion: result.question,
            saveStatus: VideoAgentSaveStatus.saved,
          ),
        );
      } else {
        // Backend did not confirm — record the failure in the chat; the draft
        // stays visible so the owner can retry.
        emit(
          state.copyWith(
            messages: [
              ...state.messages,
              if (result.reply != null)
                ChatMessage(text: result.reply!, isUser: false),
              const ChatMessage(
                text: 'Spec was not saved. Please try again.',
                isUser: false,
                status: ChatMessageStatus.error,
              ),
            ],
            agentHistory: result.history,
            chatStatus: VideoAgentChatStatus.idle,
            pendingDraft: result.draft ?? draft,
            clearPendingQuestion: result.question == null,
            pendingQuestion: result.question,
            saveStatus: VideoAgentSaveStatus.error,
          ),
        );
      }
    } catch (e, st) {
      log('VideoAgentBloc: draftConfirmed failed', error: e, stackTrace: st);
      emit(
        state.copyWith(
          saveStatus: VideoAgentSaveStatus.error,
          // Record the failure in the chat; the draft stays visible for retry.
          messages: [
            ...state.messages,
            ChatMessage(
              text: _userMessage(e),
              isUser: false,
              status: ChatMessageStatus.error,
            ),
          ],
        ),
      );
    }
  }

  /// The owner dismissed the proposal ("Tell us what to change"). Records a
  /// rejected outcome card in the chat (every action is recorded) and clears
  /// the pending draft so the right panel reverts to the current spec.
  void _onDraftDismissed(
    VideoAgentDraftDismissed event,
    Emitter<VideoAgentState> emit,
  ) {
    emit(
      state.copyWith(
        clearPendingDraft: true,
        messages: [
          ...state.messages,
          const ChatMessage(
            text: 'Proposal dismissed — tell me what to change.',
            isUser: false,
            status: ChatMessageStatus.rejected,
          ),
        ],
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _userMessage(Object e) {
    if (e is ServerException) return e.detail ?? e.message;
    if (e is NetworkException) return e.message;
    return 'Something went wrong. Please try again.';
  }
}
