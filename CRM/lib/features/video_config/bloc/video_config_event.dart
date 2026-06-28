import 'package:equatable/equatable.dart';

/// Events for the video-config agent screen.
sealed class VideoConfigEvent extends Equatable {
  const VideoConfigEvent();

  @override
  List<Object?> get props => [];
}

/// The screen opened for [gymId]: kick off refine-from-feed + load.
class VideoConfigScreenOpened extends VideoConfigEvent {
  final String gymId;

  const VideoConfigScreenOpened(this.gymId);

  @override
  List<Object?> get props => [gymId];
}

/// The owner sent [text] to the agent.
class VideoConfigMessageSent extends VideoConfigEvent {
  final String text;

  const VideoConfigMessageSent(this.text);

  @override
  List<Object?> get props => [text];
}

/// The owner confirmed the pending draft — save it.
class VideoConfigDraftConfirmed extends VideoConfigEvent {
  const VideoConfigDraftConfirmed();
}

/// The owner dismissed the pending draft — keep chatting without saving.
class VideoConfigDraftDismissed extends VideoConfigEvent {
  const VideoConfigDraftDismissed();
}

/// Dismiss a transient error so the UI can retry.
class VideoConfigErrorCleared extends VideoConfigEvent {
  const VideoConfigErrorCleared();
}
