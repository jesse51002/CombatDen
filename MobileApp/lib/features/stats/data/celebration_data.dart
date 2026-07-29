/// The payload that seeds the app-open celebration flow: the single attended
/// class the watermark just detected, plus whether a promotion is being
/// celebrated on the same open. Threaded screen-to-screen as the route
/// argument; each celebration screen reads the live streak / points / rank
/// from [MemberProfileBloc] and this for the per-class delta.
///
/// PR 3's after-class push constructs one of these directly (the deep-link
/// seam), so every field is optional with a sensible fallback. That is also
/// what makes [empty] safe as the flow's degradation: no class ([occurredAt]
/// null) and no promotion, which composes to an empty route list.
class CelebrationData {
  const CelebrationData({
    this.className = '',
    this.pointsWorth = 0,
    this.occurredAt,
    this.completedWeekdayIndices,
    this.promoted = false,
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

  /// Whether this flow opens on the belt-promotion card. Decided ONCE, by
  /// `CelebrationDetector` against the promotion watermark, and threaded from
  /// there — the cards never re-decide it, which is what keeps the post-class
  /// rank card composed out for the whole flow rather than only on the first
  /// screen that asked.
  final bool promoted;
}
