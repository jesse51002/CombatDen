import 'package:equatable/equatable.dart';

/// Events for the video-agent screen.
sealed class VideoAgentEvent extends Equatable {
  const VideoAgentEvent();

  @override
  List<Object?> get props => [];
}

/// The screen opened for [gymId]: kick off refine-from-feed + load.
class VideoAgentScreenOpened extends VideoAgentEvent {
  final String gymId;

  const VideoAgentScreenOpened(this.gymId);

  @override
  List<Object?> get props => [gymId];
}

/// The owner sent [text] to the agent.
///
/// When the message answers a pending agent question via its chips,
/// [selectedOptions] carries the chosen options so the answer renders as a
/// read-only highlighted-chips widget. Null for a typed (custom) reply.
class VideoAgentMessageSent extends VideoAgentEvent {
  final String text;
  final List<String>? selectedOptions;

  const VideoAgentMessageSent(this.text, {this.selectedOptions});

  @override
  List<Object?> get props => [text, selectedOptions];
}

/// The owner confirmed the pending draft — save it.
class VideoAgentDraftConfirmed extends VideoAgentEvent {
  const VideoAgentDraftConfirmed();
}

/// The owner dismissed the pending draft — keep chatting without saving.
class VideoAgentDraftDismissed extends VideoAgentEvent {
  const VideoAgentDraftDismissed();
}

/// Dismiss a transient error so the UI can retry.
class VideoAgentErrorCleared extends VideoAgentEvent {
  const VideoAgentErrorCleared();
}
