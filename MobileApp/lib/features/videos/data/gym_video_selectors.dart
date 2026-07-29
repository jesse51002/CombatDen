import 'package:mobile_app/features/videos/data/models/gym_video_card.dart';
import 'package:mobile_app/features/videos/data/models/video_genre.dart';

/// Pure derivations over a loaded portal feed page — no fetching, no re-sorting.
///
/// The portal returns each page ALREADY ranked (personalized) server-side, so
/// these preserve the wire order rather than re-sorting: the featured hero is
/// the first card, and carousels group by genre in first-appearance order.
/// (The retired `video_selectors.dart` re-sorted client-side because the old
/// VideoService preview wasn't globally ranked.)

/// The distinct real genres present in the feed, in first-appearance order.
/// Drives the category tab strip; untagged cards and the [VideoGenre.unknown]
/// fallback are skipped so a tab always maps to a value the portal accepts as
/// `video_type`.
List<VideoGenre> genresInFeed(List<GymVideoCard> videos) {
  final seen = <VideoGenre>{};
  final genres = <VideoGenre>[];
  for (final video in videos) {
    final tag = video.tag;
    if (tag == null || tag == VideoGenre.unknown) continue;
    if (seen.add(tag)) genres.add(tag);
  }
  return genres;
}

/// The hero video: the top card of the (already-ranked) page, or null when the
/// page is empty.
GymVideoCard? featuredCard(List<GymVideoCard> videos) =>
    videos.isEmpty ? null : videos.first;

/// One carousel per genre present, in first-appearance order, each holding that
/// genre's cards in wire order. Untagged / unknown-tag cards are skipped (they
/// have no carousel to belong to). A card appears in exactly one carousel —
/// its single [GymVideoCard.tag].
List<({VideoGenre genre, List<GymVideoCard> videos})> genreSections(
  List<GymVideoCard> videos,
) {
  final order = genresInFeed(videos);
  final claimed = {for (final genre in order) genre: <GymVideoCard>[]};
  for (final video in videos) {
    final tag = video.tag;
    if (tag == null || tag == VideoGenre.unknown) continue;
    claimed[tag]?.add(video);
  }
  return [
    for (final genre in order)
      if (claimed[genre]!.isNotEmpty)
        (genre: genre, videos: List<GymVideoCard>.unmodifiable(claimed[genre]!)),
  ];
}
