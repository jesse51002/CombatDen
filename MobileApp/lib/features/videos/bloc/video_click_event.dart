import 'package:equatable/equatable.dart';

/// Events for [VideoClickBloc].
sealed class VideoClickEvent extends Equatable {
  const VideoClickEvent();

  @override
  List<Object?> get props => [];
}

/// The member opened a video they picked out of the FEED — the hero, a genre
/// carousel, a genre "view all" list, the profile's level-up carousel.
///
/// Fire-and-forget: the bloc reports the open so the member's taste profile
/// learns from it, and never blocks, delays, or fails the YouTube launch.
///
/// Do NOT dispatch this for a recommendation the app served through
/// `VideoRecBloc` — that open is reported by `VideoRecOpened`, which also
/// stamps the served rec row. Dispatching both would log the tap twice.
class VideoOpenedFromFeed extends VideoClickEvent {
  const VideoOpenedFromFeed(this.videoId);

  /// The opened video's id (a YouTube id), the key the backend logs.
  final String videoId;

  @override
  List<Object?> get props => [videoId];
}
