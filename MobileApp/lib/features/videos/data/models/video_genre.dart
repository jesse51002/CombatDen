/// A video's genre tag — the fine-grained category the feed groups carousels
/// by, and the value a category tab sends to the portal as `video_type`.
///
/// Mirrors the Postgres `video_genre` enum (`VideoGenre` in
/// `Database/python_data/schema/video.py`). [unknown] is a client-only
/// resilient fallback for any value the app doesn't recognise — it is never a
/// real tab and is never sent back to the backend.
enum VideoGenre {
  educational,
  analysis,
  entertainment,
  news,
  interview,
  vlog,
  professional,
  clips,
  memes,
  unknown;

  /// Human-readable tab / carousel label, e.g. `professional` -> `Professional`.
  String get label =>
      name.isEmpty ? name : '${name[0].toUpperCase()}${name.substring(1)}';
}

/// Resolve a backend genre string to a [VideoGenre] without ever throwing on an
/// unrecognised value (the resilient-enum-parsing house rule). A non-genre
/// value falls back to [VideoGenre.unknown]. Used for the non-null `category`
/// on a recommendation.
VideoGenre videoGenreFromJson(Object? raw) {
  final value = raw is String ? raw : '';
  return VideoGenre.values.firstWhere(
    (g) => g.name == value,
    orElse: () => VideoGenre.unknown,
  );
}

/// Nullable variant for a card's `tag`: a missing / null wire value stays null
/// (the card is untagged); a present-but-unrecognised value becomes
/// [VideoGenre.unknown].
VideoGenre? videoGenreOrNullFromJson(Object? raw) =>
    raw == null ? null : videoGenreFromJson(raw);
