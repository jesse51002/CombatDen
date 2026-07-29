import 'package:equatable/equatable.dart';

import 'package:mobile_app/features/videos/data/models/gym_video_card.dart';
import 'package:mobile_app/features/videos/data/models/video_genre.dart';

enum VideosStatus { initial, loading, loaded, error }

/// The single state of [VideosBloc]: the current feed page plus the category
/// tabs derived from the "All" feed.
///
/// [videos] is whatever the current tab loaded — the whole feed for "All", or
/// one genre's page for a category tab (the portal filters server-side via
/// `video_type`). [availableGenres] is derived once from the "All" feed and
/// stays stable while switching tabs, so the strip doesn't collapse on a
/// single-genre load. [selectedGenre] null = the "All" tab.
class VideosState extends Equatable {
  const VideosState({
    this.status = VideosStatus.initial,
    this.videos = const [],
    this.availableGenres = const [],
    this.selectedGenre,
    this.errorMessage,
  });

  final VideosStatus status;

  /// The current tab's cards, in wire (personalized) order.
  final List<GymVideoCard> videos;

  /// The genre tabs (in feed order), derived from the "All" feed. Empty on the
  /// tag "view all" screen, which loads a single genre and shows no tabs.
  final List<VideoGenre> availableGenres;

  /// The active category, or null for the "All" tab.
  final VideoGenre? selectedGenre;

  /// The retry-able load error.
  final String? errorMessage;

  VideosState copyWith({
    VideosStatus? status,
    List<GymVideoCard>? videos,
    List<VideoGenre>? availableGenres,
    VideoGenre? selectedGenre,
    String? errorMessage,
    bool clearSelectedGenre = false,
    bool clearError = false,
  }) {
    return VideosState(
      status: status ?? this.status,
      videos: videos ?? this.videos,
      availableGenres: availableGenres ?? this.availableGenres,
      selectedGenre:
          clearSelectedGenre ? null : (selectedGenre ?? this.selectedGenre),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  List<Object?> get props => [
        status,
        videos,
        availableGenres,
        selectedGenre,
        errorMessage,
      ];
}
