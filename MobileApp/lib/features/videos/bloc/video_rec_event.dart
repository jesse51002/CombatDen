import 'package:equatable/equatable.dart';

/// Events for [VideoRecBloc].
sealed class VideoRecEvent extends Equatable {
  const VideoRecEvent();

  @override
  List<Object?> get props => [];
}

/// Load the member's next single rotating-category recommendation.
class VideoRecRequested extends VideoRecEvent {
  const VideoRecRequested();
}

/// The member opened (tapped / pressed the CTA on) the loaded recommendation:
/// record the click best-effort. Fire-and-forget — a failure must never block
/// the caller closing the screen.
class VideoRecOpened extends VideoRecEvent {
  const VideoRecOpened();
}
