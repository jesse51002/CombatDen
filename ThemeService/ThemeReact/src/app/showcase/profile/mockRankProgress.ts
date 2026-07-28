// The Profile surface's PER-MEMBER sample data, and the pure maths its graph
// plots. Ports, in one file:
//
//   * `MobileApp/lib/features/profile/data/models/billing_rank.dart` — the
//     rendered subset of `BillingRank`.
//   * `.../data/models/rank_progress_point.dart` — `RankProgressPoint`.
//   * `.../data/rank_progress_selectors.dart` — `RankTimeframe`,
//     `plottableSeries`, `windowPoints`.
//   * `_RatingGraphPainter`'s path construction from
//     `.../presentation/widgets/rank_summary/rating_graph.dart`.
//
// NONE OF IT IS A CUSTOMIZATION SLOT. The rank name, the belt progress and the
// class history are a MEMBER's numbers, exactly like the streak in
// ../celebrations/showcaseCelebrationStats.ts and the balance in
// ../rewards/mockPointsStore.ts — the theme brands the belt ART (the
// `rank_belt` / `next_rank_belt_image` slots), never the member behind it.

/** The rendered subset of `BillingRank`. */
export interface ShowcaseRank {
  readonly name: string;
  /** The sub-rank label under the name ("Stripe 2", "Division 1"); may be absent. */
  readonly subLabel?: string | undefined;
  /** Classes needed to reach the next LEAF — the denominator on the badge. */
  readonly classesTillNextStep: number;
  /** Classes attended since the last promotion — the numerator. */
  readonly classesSinceRank: number;
}

/** `RankProgressPoint`. `date` stays the backend's raw `YYYY-MM-DD` string. */
export interface ShowcaseRankPoint {
  readonly date: string;
  /** Classes accrued toward the next rank, reset to 0 at each promotion. */
  readonly classesIntoRank: number;
  /** The per-step threshold. Constant across a real series. */
  readonly classesNeeded: number;
}

/** `RankTimeframe` — the client-side window over the returned points. */
export interface ShowcaseTimeframe {
  readonly label: string;
  /** Trailing window in days; null for ALL (no window). */
  readonly days: number | null;
}

/** `RankTimeframe.values`, in declaration order. */
export const RANK_TIMEFRAMES: readonly ShowcaseTimeframe[] = Object.freeze([
  Object.freeze({ label: '1W', days: 7 }),
  Object.freeze({ label: '1M', days: 30 }),
  Object.freeze({ label: '1Y', days: 365 }),
  Object.freeze({ label: 'ALL', days: null }),
]);

/**
 * `TimeframeSelector.selected`, and the window ./RatingGraph.tsx plots — ALL.
 *
 * Pinned, because every showcase surface is a preview inside a phone frame that
 * takes no input (../rewards/RewardsTabs.tsx dropped its callbacks for the same
 * reason). It lives here rather than in either widget so the pill that reads as
 * active and the window the plot actually uses cannot drift apart when an
 * arrangement puts them on opposite ends of the screen.
 */
export const SHOWCASE_TIMEFRAME_INDEX = RANK_TIMEFRAMES.length - 1;

/** The member the Profile preview shows. Sample data — see the header. */
export const SHOWCASE_RANK: ShowcaseRank = Object.freeze({
  name: 'Blue',
  subLabel: 'Stripe 2',
  classesTillNextStep: 24,
  classesSinceRank: 17,
});

/** `_kSubtitle`'s neighbour on this screen — the topbar's sample chrome. */
export const SHOWCASE_PROFILE_STREAK_WEEKS = 3;
export const SHOWCASE_PROFILE_POINTS_LABEL = '3.4k';

/**
 * The member's activity stream for the plotted window, oldest first: the day
 * they were graded to their current rank, then every class they have attended
 * since. Mon / Wed / Fri, the cadence the rest of this member's sample numbers
 * already describe.
 *
 * ONE ENTRY PER ACTIVITY EVENT, because that is literally what the endpoint
 * returns — `MemberPortalService._walk_rank_activities` emits a point per
 * `rank_changed` / `class_attended` row of `member_activities`, never a daily or
 * weekly bucket. The dates are the gym-local days the backend buckets in, and
 * they are FIXED rather than generated from `Date.now()` so two screenshots of
 * the same theme are byte-identical; the timeframe pills read them, and the
 * preview's own pill is pinned to ALL (./RatingGraph.tsx is fed the ALL window
 * by ./RankSummarySection.tsx), so a fixed anchor windows identically forever.
 */
const SHOWCASE_RANK_ACTIVITY_DATES: readonly string[] = Object.freeze([
  // The promotion to Blue / Stripe 2 — a `rank_changed`, which resets the count.
  '2026-04-06',
  // Seventeen attended classes since, one `class_attended` each.
  '2026-04-08', '2026-04-10', '2026-04-13', '2026-04-15', '2026-04-17',
  '2026-04-20', '2026-04-22', '2026-04-24', '2026-04-27', '2026-04-29',
  '2026-05-01', '2026-05-04', '2026-05-06', '2026-05-08', '2026-05-11',
  '2026-05-13', '2026-05-15',
]);

/**
 * The plotted history: ONE RANK CYCLE — the climb from this member's last
 * promotion to where they stand today. It rises the whole way and never resets,
 * and every number in it is derived rather than chosen.
 *
 * WHY THIS AND NOT A SAWTOOTH. `classesIntoRank` does reset to 0 at each
 * promotion, so a window spanning two gradings really does saw up-and-down —
 * and the previous sample data spanned three cycles, which is what made the
 * curve read as a member losing ground twice. But a reset is not the only
 * truthful window: the endpoint returns the member's stream and the client
 * windows it, so a member whose plotted history sits inside one cycle is an
 * ordinary member, not a flattering one — it is every member between gradings,
 * and every member since a gym imported them at the rank they already held.
 * Showing that member is a choice of WHICH member to preview, which this file
 * has always been making; it is not a change to what the axis counts.
 *
 * WHY THE SHAPE IS FORCED, NOT DESIGNED. The backend's walk adds exactly ONE
 * per attended class (capped at `classesNeeded`) and emits a point for each, so
 * inside a cycle the series is `0, 1, 2, …` — and `ratingGraphPath` spaces x by
 * INDEX, not by date. The line is therefore a straight, steadily rising ramp
 * for every real member, and nothing here may bend it: the earlier data's +2 /
 * +3 / +4 weekly jumps were a bucketing the endpoint does not do. The counts
 * below are computed by the same walk rather than transcribed, so no one can
 * hand-edit a prettier number into them.
 *
 * The series ends at 17, which is `SHOWCASE_RANK.classesSinceRank` — the same
 * 17 the next-rank badge on this screen counts out as "17 / 24 classes"
 * (./NextRankSection.tsx). The graph and the badge describe one member.
 */
export const SHOWCASE_RANK_POINTS: readonly ShowcaseRankPoint[] = Object.freeze(
  SHOWCASE_RANK_ACTIVITY_DATES.map((date, index) =>
    Object.freeze({
      date,
      // `_walk_rank_activities`, verbatim: the promotion at index 0 resets the
      // running count to 0, and each class after it is +1 capped at the
      // threshold.
      classesIntoRank: Math.min(index, SHOWCASE_RANK.classesTillNextStep),
      classesNeeded: SHOWCASE_RANK.classesTillNextStep,
    }),
  ),
);

/**
 * Ports `plottableSeries`: each point's classes-into-rank as a fraction of its
 * per-step threshold, clamped to 0..1. The reset-to-0 at each promotion is
 * already in the data; the clamp is a defensive cap, and a non-positive
 * threshold maps to 0 rather than dividing by zero.
 */
export function plottableSeries(points: readonly ShowcaseRankPoint[]): readonly number[] {
  return points.map((point) => {
    if (point.classesNeeded <= 0) return 0;
    const value = point.classesIntoRank / point.classesNeeded;
    return value < 0 ? 0 : value > 1 ? 1 : value;
  });
}

/**
 * Ports `windowPoints`: filter to `timeframe`'s trailing window, anchored at
 * the LATEST point's day — so a member who last trained weeks ago still sees
 * their real recent history rather than an empty 1W. Points whose date cannot
 * be parsed are kept (never hide real data). ALL returns the points unchanged.
 */
export function windowPoints(
  points: readonly ShowcaseRankPoint[],
  timeframe: ShowcaseTimeframe,
): readonly ShowcaseRankPoint[] {
  const days = timeframe.days;
  if (days === null || points.length === 0) return points;

  let anchor: number | null = null;
  for (const point of points) {
    const parsed = Date.parse(point.date);
    if (!Number.isNaN(parsed)) anchor = parsed;
  }
  if (anchor === null) return points;

  const cutoff = anchor - days * 24 * 60 * 60 * 1000;
  return points.filter((point) => {
    const parsed = Date.parse(point.date);
    return Number.isNaN(parsed) || parsed >= cutoff;
  });
}

/**
 * `_RatingGraphPainter.paint`'s path, as an SVG `d` string over a `width` x
 * `height` viewBox.
 *
 * The control points are the painter's own Catmull-Rom-to-Bézier conversion,
 * ported arithmetic-for-arithmetic — including the two ENDPOINT DUPLICATIONS
 * (`p0 = points[0]` on the first segment, `p3 = points[i + 1]` on the last),
 * which are what keep the curve from overshooting at the ends. Returns an empty
 * string for a series with fewer than two points, matching the painter's own
 * early return; the caller renders the empty state instead.
 */
export function ratingGraphPath(
  series: readonly number[],
  width: number,
  height: number,
): string {
  if (series.length < 2) return '';

  const points = series.map((value, index) => ({
    x: width * (index / (series.length - 1)),
    y: height * (1 - (value < 0 ? 0 : value > 1 ? 1 : value)),
  }));

  const at = (index: number): { x: number; y: number } => {
    const point = points[index];
    // Unreachable: every index below is clamped into range before the call.
    return point ?? { x: 0, y: 0 };
  };

  const first = at(0);
  let d = `M ${round(first.x)} ${round(first.y)}`;
  for (let i = 0; i < points.length - 1; i++) {
    const p0 = at(i === 0 ? 0 : i - 1);
    const p1 = at(i);
    const p2 = at(i + 1);
    const p3 = at(i + 2 < points.length ? i + 2 : i + 1);

    const cp1x = p1.x + (p2.x - p0.x) / 6;
    const cp1y = p1.y + (p2.y - p0.y) / 6;
    const cp2x = p2.x - (p3.x - p1.x) / 6;
    const cp2y = p2.y - (p3.y - p1.y) / 6;

    d += ` C ${round(cp1x)} ${round(cp1y)}, ${round(cp2x)} ${round(cp2y)}, ${round(p2.x)} ${round(p2.y)}`;
  }
  return d;
}

/** Three decimals is well under a device pixel and keeps the `d` readable. */
function round(value: number): number {
  return Math.round(value * 1000) / 1000;
}
