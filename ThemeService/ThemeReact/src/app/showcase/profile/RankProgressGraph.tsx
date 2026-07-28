// Ports ../../../../../../MobileApp/lib/features/profile/presentation/widgets/
// rank_summary/{rank_progress_graph,rating_graph,timeframe_selector}.dart —
// the member's classes-into-rank sawtooth with the classes axis bracketed on
// the right edge, over the 1W / 1M / 1Y / ALL pill row.
//
// THREE DART FILES, ONE HERE. `rank_progress_graph.dart` is a bloc-driven shell
// whose loading and retryable-error branches await a fetch; the preview's
// series is a bundled constant (./mockRankProgress.ts), so those two branches
// have no reachable input and are not ported — an unreachable spinner is a lie
// about what the phone does. What survives is `_LoadedGraph`, which is exactly
// `RatingGraph` over `TimeframeSelector`, so they land in one file rather than
// three files of two elements each.
//
// A CANVAS BECOMES AN SVG PATH. `_RatingGraphPainter` walks the series into a
// Catmull-Rom-to-Bézier path; the same arithmetic produces an SVG `d` string in
// ./mockRankProgress.ts, where it can be asserted without a renderer. There is
// no per-frame value here — the curve is static — so there is nothing for a
// canvas to buy.
//
// THE PILLS DO NOT WINDOW ANYTHING, and that is the island's rule rather than a
// gap: every showcase surface is a preview inside a phone frame that takes no
// input, which is why ../rewards/RewardsTabs.tsx dropped its callbacks and
// ../videos/VideoCategoryTabs.tsx renders labels. ALL is the pinned selection,
// and it is the one that shows the whole sawtooth — the selection a screenshot
// wants anyway.

import { cx } from '../cx';

import styles from './RankProgressGraph.module.css';
import type { ShowcaseRankPoint } from './mockRankProgress';
import {
  RANK_TIMEFRAMES,
  plottableSeries,
  ratingGraphPath,
  windowPoints,
} from './mockRankProgress';

/**
 * `_kGraphAspect` — the graph's fixed footprint, shared by the plot and the
 * empty state so the layout never jumps. A per-screen layout ratio, not a token.
 */
const GRAPH_WIDTH = 393;
const GRAPH_HEIGHT = 196.5;

/** `_kStrokeWidth`, in the viewBox's units. */
const STROKE_WIDTH = 3;

/** `TimeframeSelector.selected` — pinned; see the header. */
const SELECTED_TIMEFRAME_INDEX = RANK_TIMEFRAMES.length - 1;

export interface RankProgressGraphProps {
  points: readonly ShowcaseRankPoint[];
}

export function RankProgressGraph({ points }: RankProgressGraphProps) {
  const timeframe = RANK_TIMEFRAMES[SELECTED_TIMEFRAME_INDEX];
  const windowed = timeframe === undefined ? points : windowPoints(points, timeframe);
  const series = plottableSeries(windowed);
  // `windowed.isNotEmpty ? windowed.last.classesNeeded : 0`.
  const needed = windowed.length === 0 ? 0 : (windowed[windowed.length - 1]?.classesNeeded ?? 0);
  const path = ratingGraphPath(series, GRAPH_WIDTH, GRAPH_HEIGHT);

  return (
    // `Column(mainAxisSize: min, spacing: spacingLarge)`.
    <div className={styles.graph}>
      {/* `Padding(horizontal: screenHorizontalPadding) > AspectRatio(_kGraphAspect)`. */}
      <div className={styles.plotInset}>
        <div className={styles.plot}>
          {path === '' ? (
            // `_GraphEmpty` — a series with fewer than two points.
            <p className={styles.empty}>No rank history yet.</p>
          ) : (
            <>
              <svg
                className={styles.svg}
                viewBox={`0 0 ${String(GRAPH_WIDTH)} ${String(GRAPH_HEIGHT)}`}
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
                `ThresholdLabel`, the promotion line at the top and 0 at the
                bottom. The top one is hidden at a non-positive threshold,
                exactly as Dart's `if (classesNeeded > 0)` has it.
              */}
              {needed > 0 && <span className={styles.thresholdTop}>{String(needed)}</span>}
              <span className={styles.thresholdBottom}>0</span>
            </>
          )}
        </div>
      </div>
      {/* `TimeframeSelector` — `Row(center, min, spacing: spacingBig)`. */}
      <div className={styles.timeframes}>
        {RANK_TIMEFRAMES.map((entry, index) => (
          <span
            key={entry.label}
            className={cx(styles.pill, index === SELECTED_TIMEFRAME_INDEX && styles.pillActive)}
          >
            {entry.label}
          </span>
        ))}
      </div>
    </div>
  );
}
