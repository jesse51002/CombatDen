import 'package:equatable/equatable.dart';

import 'package:crm/features/video_config/data/models/video_config_models.dart';

/// On-open load sequence: refine-from-feed → getConfig.
enum VideoConfigLoadStatus {
  /// Not started yet.
  initial,

  /// Running refine-from-feed (brief "Improving…" banner).
  refining,

  /// Fetching the current saved config after refine.
  loading,

  /// Config loaded successfully.
  loaded,

  /// No config exists yet (both refine and getConfig returned 404).
  empty,

  /// Load failed.
  error,
}

/// Status of the in-session chat.
enum VideoConfigChatStatus {
  idle,
  typing,
}

/// Status of the save-draft operation.
enum VideoConfigSaveStatus {
  idle,
  saving,

  /// Save succeeded — the pending draft has been cleared and [savedConfig]
  /// reflects the committed result.
  saved,

  error,
}

class VideoConfigState extends Equatable {
  // ── Load ──
  final VideoConfigLoadStatus loadStatus;

  /// The last committed config (null = none yet).
  final VideoConfigView? savedConfig;

  // ── Chat ──
  final List<ChatMessage> messages;

  /// The full agent history from the last turn — sent back verbatim on
  /// every subsequent turn so the stateless backend can resume context.
  /// Null before any turn has completed.
  final List<dynamic>? agentHistory;

  final VideoConfigChatStatus chatStatus;

  // ── Draft ──
  /// Non-null when the agent has proposed a config that awaits confirmation.
  final VideoConfigDraft? pendingDraft;

  // ── Save ──
  final VideoConfigSaveStatus saveStatus;

  // ── Error ──
  final String? error;

  const VideoConfigState({
    this.loadStatus = VideoConfigLoadStatus.initial,
    this.savedConfig,
    this.messages = const [],
    this.agentHistory,
    this.chatStatus = VideoConfigChatStatus.idle,
    this.pendingDraft,
    this.saveStatus = VideoConfigSaveStatus.idle,
    this.error,
  });

  VideoConfigState copyWith({
    VideoConfigLoadStatus? loadStatus,
    VideoConfigView? savedConfig,
    bool clearSavedConfig = false,
    List<ChatMessage>? messages,
    List<dynamic>? agentHistory,
    bool clearAgentHistory = false,
    VideoConfigChatStatus? chatStatus,
    VideoConfigDraft? pendingDraft,
    bool clearPendingDraft = false,
    VideoConfigSaveStatus? saveStatus,
    String? error,
    bool clearError = false,
  }) => VideoConfigState(
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
    saveStatus,
    error,
  ];
}
