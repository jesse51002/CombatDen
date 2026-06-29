/// Data models for the video-agent domain.
///
/// [VideoSpecView] — the full saved spec returned by GET /video-spec.
/// [VideoSpecDraft] — the criteria-only payload proposed by the agent and
///   sent as `accepted_spec` when the owner confirms.
/// [AgentQuestion] — a multiple-choice question the agent may ask.
/// [ChatMessage] — a single message in the in-session chat history (UI only,
///   not serialised to the backend).
/// [AgentTurnResult] — the parsed body of POST /video-agent.
library;

/// The saved video spec for a gym, as returned by the backend.
/// Mirrors `VideoSpecView` from `video_schema.py`.
///
/// Note: [queries] is kept in the model (the backend includes it) but is
/// intentionally never rendered in the UI — the gym owner does not see
/// the search queries.
class VideoSpecView {
  final String gymId;
  final List<String> disciplines;
  final String videosDesc;
  final String avoidDesc;
  final String? shortVideosDesc;
  final String? shortAvoidDesc;
  final List<String> queries;
  final String source;
  final String? importedFrom;

  const VideoSpecView({
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

  factory VideoSpecView.fromJson(Map<String, dynamic> json) =>
      VideoSpecView(
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

/// The criteria-only draft proposed by the agent or sent back as
/// `accepted_spec` when the owner confirms.
///
/// Mirrors the criteria fields of `VideoSpecCriteria` from `video_schema.py`.
/// Does NOT include `queries` — queries are generated server-side and are
/// never shown to the gym owner.
class VideoSpecDraft {
  final List<String> disciplines;
  final String videosDesc;
  final String avoidDesc;
  final String? shortVideosDesc;
  final String? shortAvoidDesc;

  const VideoSpecDraft({
    required this.disciplines,
    required this.videosDesc,
    required this.avoidDesc,
    this.shortVideosDesc,
    this.shortAvoidDesc,
  });

  factory VideoSpecDraft.fromJson(Map<String, dynamic> json) =>
      VideoSpecDraft(
        disciplines:
            (json['disciplines'] as List?)
                ?.whereType<String>()
                .toList(growable: false) ??
            const [],
        videosDesc: (json['videos_desc'] as String?) ?? '',
        avoidDesc: (json['avoid_desc'] as String?) ?? '',
        shortVideosDesc: json['short_videos_desc'] as String?,
        shortAvoidDesc: json['short_avoid_desc'] as String?,
      );

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{
      'disciplines': disciplines,
      'videos_desc': videosDesc,
      'avoid_desc': avoidDesc,
    };
    if (shortVideosDesc != null) m['short_videos_desc'] = shortVideosDesc;
    if (shortAvoidDesc != null) m['short_avoid_desc'] = shortAvoidDesc;
    return m;
  }
}

/// A multiple-choice question the agent may propose on any turn.
///
/// Mirrors `AgentQuestion` from `video_schema.py`.
/// When [multiSelect] is false the owner picks exactly one option;
/// when true they may select any combination before sending.
class AgentQuestion {
  final String question;
  final List<String> options;
  final bool multiSelect;

  const AgentQuestion({
    required this.question,
    required this.options,
    this.multiSelect = false,
  });

  factory AgentQuestion.fromJson(Map<String, dynamic> json) =>
      AgentQuestion(
        question: (json['question'] as String?) ?? '',
        options:
            (json['options'] as List?)
                ?.whereType<String>()
                .toList(growable: false) ??
            const [],
        multiSelect: (json['multi_select'] as bool?) ?? false,
      );
}

/// Outcome marker for a special chat card. [saved] (proposal accepted),
/// [rejected] (proposal dismissed), and [error] (a failed turn/save) render as
/// coloured outcome widgets; [none] is an ordinary message. Every action is
/// recorded in the chat — there are no out-of-chat banners.
enum ChatMessageStatus { none, saved, rejected, error }

/// One message in the in-session chat UI. Not sent to the backend — the
/// backend's stateless history ([AgentTurnResult.history]) is the durable
/// record; this is the display layer only.
class ChatMessage {
  final String text;
  final bool isUser;

  /// When this user message answers an [AgentQuestion], the full list of
  /// options it offered — rendered read-only with [selectedOptions]
  /// highlighted. Null for ordinary messages.
  final List<String>? options;

  /// The options the owner selected (a subset of [options]); empty when they
  /// typed a custom reply instead, in which case [text] shows below the
  /// unselected options.
  final List<String> selectedOptions;

  /// Outcome marker (agent messages): [ChatMessageStatus.saved] (accepted) or
  /// [ChatMessageStatus.rejected] (dismissed) render as a coloured outcome
  /// widget; [ChatMessageStatus.none] is an ordinary message.
  final ChatMessageStatus status;

  const ChatMessage({
    required this.text,
    required this.isUser,
    this.options,
    this.selectedOptions = const [],
    this.status = ChatMessageStatus.none,
  });
}

/// Parsed response from POST /video-agent.
///
/// Exactly one of [reply], [draft], or [question] is set per turn
/// (per the backend contract), though the model accepts any combination.
class AgentTurnResult {
  /// The agent's reply text, or null if the agent returned a draft/question.
  final String? reply;

  /// A proposed spec draft; non-null when the agent is ready to commit.
  final VideoSpecDraft? draft;

  /// A multiple-choice question for the owner to answer; non-null when the
  /// agent needs clarification before proposing a draft.
  final AgentQuestion? question;

  /// The full conversation history — send this back verbatim on the
  /// next turn so the stateless backend can resume context.
  /// Null before any turn has completed.
  final List<dynamic> history;

  /// True when the backend committed a save on this turn (i.e. an
  /// `accepted_spec` was provided and the spec was persisted).
  final bool saved;

  const AgentTurnResult({
    required this.reply,
    required this.draft,
    this.question,
    required this.history,
    required this.saved,
  });

  factory AgentTurnResult.fromJson(Map<String, dynamic> json) =>
      AgentTurnResult(
        reply: json['reply'] as String?,
        draft: json['draft'] == null
            ? null
            : VideoSpecDraft.fromJson(
                (json['draft'] as Map).cast<String, dynamic>(),
              ),
        question: json['question'] == null
            ? null
            : AgentQuestion.fromJson(
                (json['question'] as Map).cast<String, dynamic>(),
              ),
        history: (json['history'] as List?) ?? const [],
        saved: (json['saved'] as bool?) ?? false,
      );
}
