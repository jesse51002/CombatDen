import 'package:equatable/equatable.dart';

import 'package:crm/features/video_agent/data/models/video_agent_models.dart';

/// On-open load sequence: refine-from-feed → getConfig.
enum VideoAgentLoadStatus {
  /// Not started yet.
  initial,

  /// Running refine-from-feed (brief "Improving…" banner).
  refining,

  /// Fetching the current saved spec after refine.
  loading,

  /// Spec loaded successfully.
  loaded,

  /// No spec exists yet (both refine and getConfig returned 404).
  empty,

  /// Load failed.
  error,
}

/// Status of the in-session chat.
enum VideoAgentChatStatus {
  idle,
  typing,
}

/// Status of the save-draft operation.
enum VideoAgentSaveStatus {
  idle,
  saving,

  /// Save succeeded — the pending draft has been cleared and [savedConfig]
  /// reflects the committed result. The chat stays open.
  saved,

  error,
}

class VideoAgentState extends Equatable {
  // ── Load ──
  final VideoAgentLoadStatus loadStatus;

  /// The last committed spec (null = none yet).
  final VideoSpecView? savedConfig;

  // ── Chat ──
  final List<ChatMessage> messages;

  /// The full agent history from the last turn — sent back verbatim on
  /// every subsequent turn so the stateless backend can resume context.
  /// Null before any turn has completed.
  final List<dynamic>? agentHistory;

  final VideoAgentChatStatus chatStatus;

  // ── Draft ──
  /// Non-null when the agent has proposed a spec that awaits confirmation.
  final VideoSpecDraft? pendingDraft;

  // ── Question ──
  /// Non-null when the agent has asked a multiple-choice question.
  /// Cleared as soon as the owner sends any message (typed or chip-selected).
  final AgentQuestion? pendingQuestion;

  // ── Save ──
  final VideoAgentSaveStatus saveStatus;

  // ── Error ──
  final String? error;

  const VideoAgentState({
    this.loadStatus = VideoAgentLoadStatus.initial,
    this.savedConfig,
    this.messages = const [],
    this.agentHistory,
    this.chatStatus = VideoAgentChatStatus.idle,
    this.pendingDraft,
    this.pendingQuestion,
    this.saveStatus = VideoAgentSaveStatus.idle,
    this.error,
  });

  VideoAgentState copyWith({
    VideoAgentLoadStatus? loadStatus,
    VideoSpecView? savedConfig,
    bool clearSavedConfig = false,
    List<ChatMessage>? messages,
    List<dynamic>? agentHistory,
    bool clearAgentHistory = false,
    VideoAgentChatStatus? chatStatus,
    VideoSpecDraft? pendingDraft,
    bool clearPendingDraft = false,
    AgentQuestion? pendingQuestion,
    bool clearPendingQuestion = false,
    VideoAgentSaveStatus? saveStatus,
    String? error,
    bool clearError = false,
  }) => VideoAgentState(
    loadStatus: loadStatus ?? this.loadStatus,
    savedConfig: clearSavedConfig
        ? null
        : savedConfig ?? this.savedConfig,
    messages: messages ?? this.messages,
    agentHistory: clearAgentHistory
        ? null
        : agentHistory ?? this.agentHistory,
    chatStatus: chatStatus ?? this.chatStatus,
    pendingDraft: clearPendingDraft
        ? null
        : pendingDraft ?? this.pendingDraft,
    pendingQuestion: clearPendingQuestion
        ? null
        : pendingQuestion ?? this.pendingQuestion,
    saveStatus: saveStatus ?? this.saveStatus,
    error: clearError ? null : error ?? this.error,
  );

  @override
  List<Object?> get props => [
    loadStatus,
    savedConfig,
    messages,
    agentHistory,
    chatStatus,
    pendingDraft,
    pendingQuestion,
    saveStatus,
    error,
  ];
}
