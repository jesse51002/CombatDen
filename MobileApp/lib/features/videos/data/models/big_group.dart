/// The coarse two-way sort the backend derives from a video's [VideoGenre]:
/// educational vs entertainment.
///
/// Mirrors the videos-domain `BigGroup` enum
/// (`FastApiBackend/src/videos/schema/videos_big_group.py`). Sent down on each
/// card as a server-computed field; the app renders it verbatim and owns no
/// mapping. [unknown] is the client-only resilient fallback.
enum BigGroup {
  educational,
  entertainment,
  unknown;

  /// Human-readable label, e.g. `entertainment` -> `Entertainment`.
  String get label =>
      name.isEmpty ? name : '${name[0].toUpperCase()}${name.substring(1)}';
}

/// Nullable resilient parse for a card's `big_group`: null when absent,
/// [BigGroup.unknown] when present but unrecognised.
BigGroup? bigGroupOrNullFromJson(Object? raw) {
  if (raw is! String) return null;
  return BigGroup.values.firstWhere(
    (g) => g.name == raw,
    orElse: () => BigGroup.unknown,
  );
}
