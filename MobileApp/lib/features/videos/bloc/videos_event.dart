import 'package:equatable/equatable.dart';

import 'package:mobile_app/core/refresh/refresh_signal.dart';
import 'package:mobile_app/features/videos/data/models/video_genre.dart';

/// Events for [VideosBloc].
sealed class VideosEvent extends Equatable {
  const VideosEvent();

  @override
  List<Object?> get props => [];
}

/// Initial load of the "All" feed — the whole personalized page, from which the
/// category tab strip is derived. When [initialGenre] is set (a deep link that
/// opens straight to a category), the same handler then loads that genre so the
/// tab strip AND the pre-selected category both land, race-free in one handler.
class VideosLoadRequested extends VideosEvent {
  const VideosLoadRequested({this.initialGenre});

  final VideoGenre? initialGenre;

  @override
  List<Object?> get props => [initialGenre];
}

/// Pull-to-refresh: re-fetch the CURRENT tab's feed without blanking it. The
/// selected genre is kept (a pull is not a tab change), and the "All" tab
/// re-derives the genre strip so a gym that just published its first video of
/// a genre grows the tab for it.
///
/// [done] is the completion side-channel — see [RefreshSignal].
class VideosRefreshRequested extends VideosEvent {
  const VideosRefreshRequested([this.done]);

  final RefreshSignal? done;
}

/// A category tab was selected: reload the feed filtered to [genre] via the
/// portal's `video_type`. A null [genre] is the "All" tab (no filter), which
/// also re-derives the tab strip. Reused by the tag "view all" screen to load a
/// single genre directly.
class VideosCategorySelected extends VideosEvent {
  const VideosCategorySelected(this.genre);

  final VideoGenre? genre;

  @override
  List<Object?> get props => [genre];
}
