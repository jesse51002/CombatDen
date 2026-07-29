// Ports ../../../../../../MobileApp/lib/features/profile/presentation/widgets/
// rank_summary/rating_graph.dart — the plot on its own: the member's
// classes-into-rank line with the classes axis bracketed on the right edge,
// `classesNeeded` (the promotion line) at the top and `0` at the bottom.
//
// TWO DART REVISIONS, ONE FILE. The `size` / `bleed` / `card` API is the
// layout-formats revision's (`RatingGraphSize.sm|md|lg`, the raised surface,
// the full-bleed run to the screen edges) — the knobs the five arrangements
// turn. The DATA is the shipping member app's: a real `series` +
// `classesNeeded` with the two axis labels, not that revision's mock
// rating-over-time series annotated with belt names. Its `RatingGraph` reads a
// module-level `mockRatingGraphSeries` and drops the classes axis, which is a
// regression against `MobileApp`'s own `rank_progress_graph.dart` on main; this
// port keeps the shipped semantics and takes only the sizing from it.
//
// A CANVAS BECOMES AN SVG PATH. `_RatingGraphPainter` walks the series into a
// Catmull-Rom-to-Bézier path; the same arithmetic produces an SVG `d` string in
// ./mockRankProgress.ts, where it can be asserted without a renderer. There is
// no per-frame value here — the curve is static — so there is nothing for a
// canvas to buy.

import { RANK_PART } from './rankParts';
import styles from './RatingGraph.module.css';
import type { ShowcaseRankPoint } from './mockRankProgress';
import {
  RANK_TIMEFRAMES,
  SHOWCASE_TIMEFRAME_INDEX,
  plottableSeries,
  ratingGraphPath,
  windowPoints,
} from './mockRankProgress';

/**
 * `_kNominalWidth` / `_kNominalHeight` and the two re-proportioned heights.
 * Per-screen layout ratios, not tokens — the Dart spells them as file-local
 * consts too.
 */
const NOMINAL_WIDTH = 393;
const HEIGHTS = Object.freeze({ sm: 110, md: 196.5, lg: 248 });

/** `_kStrokeWidth`, in the viewBox's units. */
const STROKE_WIDTH = 3;

/** `RatingGraphSize`. */
export type RatingGraphSize = 'sm' | 'md' | 'lg';

export interface RatingGraphProps {
  points: readonly ShowcaseRankPoint[];
  /** How much room the plot gets. `md` is the shipped box. */
  size?: RatingGraphSize;
  /** Run the plot to the screen edges instead of inside the standard gutter. */
  bleed?: boolean;
  /** Seat the plot on a raised surface. */
  card?: boolean;
}

export function RatingGraph({ points, size = 'md', bleed = false, card = false }: RatingGraphProps) {
  // `_LoadedGraph`'s three lines, and the reason the window lives with the
  // series rather than with the pills: an arrangement may put the selector two
  // screens away from the plot (./RankSummarySection.tsx vs ./layouts/
  // RankBeltHero.tsx) and the two still have to agree on what is being shown.
  const timeframe = RANK_TIMEFRAMES[SHOWCASE_TIMEFRAME_INDEX];
  const windowed = timeframe === undefined ? points : windowPoints(points, timeframe);
  const series = plottableSeries(windowed);
  // `windowed.isNotEmpty ? windowed.last.classesNeeded : 0`.
  const needed = windowed.length === 0 ? 0 : (windowed[windowed.length - 1]?.classesNeeded ?? 0);
  const height = HEIGHTS[size];
  const path = ratingGraphPath(series, NOMINAL_WIDTH, height);

  const plot = (
    // `AspectRatio(aspectRatio: _kNominalWidth / _height) > Stack(...)`.
    <div
      className={styles.plot}
      style={{ aspectRatio: `${String(NOMINAL_WIDTH)} / ${String(height)}` }}
      data-rank-part={RANK_PART.ratingGraph}
    >
      {path === '' ? (
        // `_GraphEmpty` — a series with fewer than two points.
        <p className={styles.empty}>No rank history yet.</p>
      ) : (
        <>
          <svg
            className={styles.svg}
            viewBox={`0 0 ${String(NOMINAL_WIDTH)} ${String(height)}`}
            fill="none"
            aria-hidden="true"
            focusable="false"
          >
            <path
              d={path}
              stroke="currentColor"
              strokeWidth={STROKE_WIDTH}
              strokeLinecap="round"
              strokeLinejoin="round"
            />
          </svg>
          {/*
            `Positioned(right: 0, top: 0)` / `(right: 0, bottom: 0)` —
            `ThresholdLabel`, the promotion line at the top and 0 at the bottom.
            The top one is hidden at a non-positive threshold, exactly as Dart's
            `if (classesNeeded > 0)` has it. Pinned to the box's own corners, so
            a shorter plot moves them with it and no offset needs re-scaling.
          */}
          {needed > 0 && <span className={styles.thresholdTop}>{String(needed)}</span>}
          <span className={styles.thresholdBottom}>0</span>
        </>
      )}
    </div>
  );

  // `if (bleed) return plot;` — otherwise `Padding(horizontal:
  // screenHorizontalPadding)`, with `_Surface` NESTED inside that padding when
  // asked for (the card's own `spacingMedium` sits in from the gutter, it does
  // not replace it).
  if (bleed) return plot;
  return (
    <div className={styles.inset}>{card ? <div className={styles.surface}>{plot}</div> : plot}</div>
  );
}
