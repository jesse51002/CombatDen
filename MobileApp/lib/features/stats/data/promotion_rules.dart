// Pure decision logic for the belt-promotion card — no I/O, no widgets, fully
// unit-testable without shared_preferences.

/// What the per-member promotion watermark says to do with the promotion the
/// profile just carried.
enum PromotionDecision {
  /// No watermark yet — SEED it silently to the current promotion and fire
  /// NOTHING, so a first run / reinstall / member switch never replays a belt
  /// the member was given months ago.
  seedSilently,

  /// A promotion the member has not seen — celebrate it once, then advance.
  fire,

  /// Already seen, or nothing to show.
  skip,
}

/// The watermark rule: no promotion skips, a null watermark seeds silently, an
/// id the member has already seen is skipped, and anything else fires.
///
/// **Compare by EQUALITY, never by ordering.** `activity_id` is an opaque,
/// immutable, unique id — the backend says so explicitly, and that a timestamp
/// "would be a weaker key (two rows can share an instant, and clock /
/// precision differences across the wire make equality fragile)". Someone will
/// eventually want to make this ordered, or to key it on `promoted_at`; both
/// are wrong. It is safe to be unordered because the server only ever surfaces
/// the NEWEST genuine promotion, so a different id is by construction a newer
/// one. `promoted_at` is for display and ordering only.
///
/// This is the one difference from `decideCelebration`, which compares
/// timestamps with `isAfter` because an attendance instant genuinely is its
/// own ordering key. Everything else — including seeding silently on null —
/// is deliberately identical.
PromotionDecision decidePromotion({
  required String? lastSeenActivityId,
  required String? activityId,
}) {
  if (activityId == null) return PromotionDecision.skip;
  if (lastSeenActivityId == null) return PromotionDecision.seedSilently;
  if (activityId == lastSeenActivityId) return PromotionDecision.skip;
  return PromotionDecision.fire;
}
