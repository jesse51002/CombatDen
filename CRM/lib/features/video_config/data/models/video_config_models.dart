/// Data models for the video-config domain.
///
/// [VideoConfigView] — the full saved config returned by GET / and PUT /.
/// [VideoConfigDraft] — the mutable payload sent to PUT / and returned by
///   the agent when it proposes a config.
/// [ChatMessage] — a single message in the in-session chat history (UI only,
///   not serialised to the backend).
/// [AgentTurnResult] — the parsed body of POST /agent.
library;

/// The saved video-config for a gym, as returned by the backend.
/// Mirrors `VideoConfigView` from `video_schema.py`.
class VideoConfigView {
  final String gymId;
  final List<String> disciplines;
  final String videosDesc;
  final String avoidDesc;
  final String? shortVideosDesc;
  final String? shortAvoidDesc;
  final List<String> queries;
  final String source;
  final String? importedFrom;

  const VideoConfigView({
    required this.gymId,
    required this.disciplines,
    required this.videosDesc,
    required this.avoidDesc,
    this.shortVideosDesc,
    this.shortAvoidDesc,
    required this.queries,
    required this.source,
    this.importedFrom,
  });

  factory VideoConfigView.fromJson(Map<String, dynamic> json) =>
      VideoConfigView(
        gymId: (json['gym_id'] as String?) ?? '',
        disciplines:
            (json['disciplines'] as List?)
                ?.whereType<String>()
                .toList(growable: false) ??
            const [],
        videosDesc: (json['videos_desc'] as String?) ?? '',
        avoidDesc: (json['avoid_desc'] as String?) ?? '',
        shortVideosDesc: json['short_videos_desc'] as String?,
        shortAvoidDesc: json['short_avoid_desc'] as String?,
        queries:
            (json['queries'] as List?)
                ?.whereType<String>()
                .toList(growable: false) ??
            const [],
        source: (json['source'] as String?) ?? '',
        importedFrom: json['imported_from'] as String?,
      );
}

/// The mutable payload sent to PUT / and proposed by the agent.
/// Mirrors `VideoConfigDraft` from `video_schema.py`.
class VideoConfigDraft {
  final List<String> disciplines;
  final String videosDesc;
  final String avoidDesc;
  final String? shortVideosDesc;
  final String? shortAvoidDesc;
  final List<String> queries;

  const VideoConfigDraft({
    required this.disciplines,
    required this.videosDesc,
    required this.avoidDesc,
    this.shortVideosDesc,
    this.shortAvoidDesc,
    required this.queries,
  });

  factory VideoConfigDraft.fromJson(Map<String, dynamic> json) =>
      VideoConfigDraft(
        disciplines:
            (json['disciplines'] as List?)
                ?.whereType<String>()
                .toList(growable: false) ??
            const [],
        videosDesc: (json['videos_desc'] as String?) ?? '',
        avoidDesc: (json['avoid_desc'] as String?) ?? '',
        shortVideosDesc: json['short_videos_desc'] as String?,
        shortAvoidDesc: json['short_avoid_desc'] as String?,
        queries:
            (json['queries'] as List?)
                ?.whereType<String>()
                .toList(growable: false) ??
            const [],
      );

  Map<String, dynamic> toJson() => {
    'disciplines': disciplines,
    'videos_desc': videosDesc,
    'avoid_desc': avoidDesc,
    if (shortVideosDesc != null) 'short_videos_desc': shortVideosDesc,
    if (shortAvoidDesc != null) 'short_avoid_desc': shortAvoidDesc,
    'queries': queries,
  };
}

/// One message in the in-session chat UI. Not sent to the backend — the
/// backend's stateless history ([AgentTurnResult.history]) is the durable
/// record; this is the display layer only.
class ChatMessage {
  final String text;
  final bool isUser;

  const ChatMessage({required this.text, required this.isUser});
}

/// Parsed response from POST /agent.
class AgentTurnResult {
  /// The agent's reply text, or null if the agent only returned a draft.
  final String? reply;

  /// A proposed config draft; non-null when the agent is ready to commit.
  final VideoConfigDraft? draft;

  /// The full conversation history — send this back verbatim on the
  /// next turn so the stateless backend can resume context.
  final List<dynamic> history;

  const AgentTurnResult({
    required this.reply,
    required this.draft,
    required this.history,
  });

  factory AgentTurnResult.fromJson(Map<String, dynamic> json) =>
      AgentTurnResult(
        reply: json['reply'] as String?,
        draft: json['draft'] == null
            ? null
            : VideoConfigDraft.fromJson(
                (json['draft'] as Map).cast<String, dynamic>(),
              ),
        history: (json['history'] as List?) ?? const [],
      );
}
