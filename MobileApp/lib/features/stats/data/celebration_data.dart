/// The per-occurrence payload that seeds the post-class celebration flow — the
/// single attended class the watermark just detected. Threaded screen-to-screen
/// as the route argument; each celebration screen reads the live streak /
/// points / rank from [MemberProfileBloc] and this for the per-class delta.
///
/// PR 3's after-class push constructs one of these directly (the deep-link
/// seam), so every field is optional with a sensible fallback.
class CelebrationData {
  const CelebrationData({
    this.className = '',
    this.pointsWorth = 0,
    this.occurredAt,
    this.completedWeekdayIndices,
  });

  /// The empty fallback used when a celebration route is entered without an
  /// argument (keeps the flow renderable for verification).
  const CelebrationData.empty() : this();

  /// The attended class's name (carried for PR 3 / analytics).
  final String className;

  /// Points the attended class was worth — the streak card's "+N points"
  /// subtitle and the points card's count-up delta.
  final int pointsWorth;

  /// The attendance instant (the watermark key). Null only on [empty].
  final DateTime? occurredAt;

  /// Sunday-first (0 = Sun … 6 = Sat) weekday indices trained THIS week,
  /// derived from the class-history head at detection time. Null when the
  /// caller couldn't derive it (e.g. the PR 3 deep-link) — the streak card then
  /// highlights only the day just attended.
  final List<int>? completedWeekdayIndices;
}
