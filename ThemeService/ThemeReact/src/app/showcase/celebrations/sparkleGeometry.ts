// The pure half of ./SparkleBurst.tsx, which ports
// ../../../../../../CRM/lib/showcase/celebrations/sparkle_burst.dart.
//
// Two things live here because neither is a component and both are worth
// pinning in a test: the SHAPE and the CLOCK.
//
// THE SHAPE. Dart draws the 8-point star with a `CustomPainter` —
// `_SparkleStarPainter.paint` walks eight points on a 24-unit box scaled by
// `s = size.width / 24` and fills the closed path. The web has no painter on a
// decorative box, and adding an inline SVG per particle would be 12 extra
// elements for a fill. A `clip-path: polygon(...)` over a plain background is
// the same drawing: the point list is the Dart's verbatim, normalised to
// percentages of the box, so ONE class scales to every particle size.
//
// THE CLOCK. Dart runs one controller over `CelebrationTimings.sparkleWindow`
// and slices it per particle:
//
//   stagger = (index / n) * 0.65        where the particle's fade STARTS
//   localT  = ((t - stagger) / 0.35)    how long that fade LASTS
//
// Both are fractions of the window, so they port as a wall-clock delay and a
// wall-clock duration and the whole burst becomes 12 CSS animations with
// nothing left in JS. The 0.35 slice is 217ms of the 620ms window, which is
// what `CelebrationTimings.sparkleFadeMs` (220) restates approximately — the
// fraction is what the Dart actually evaluates, so the fraction is what ports.

import { CelebrationTimings } from 'theme-react';

/** One entry of `SparkleBurst._scatter`: `(size, dx, dy, opacity)`. */
export interface SparkleParticle {
  /** Edge length of the star's box, in px. Not scaled by the burst size. */
  readonly size: number;
  /** Offset from the burst's centre, in px. */
  readonly dx: number;
  readonly dy: number;
  /** The opacity the particle settles at — `eased * s.$4` at `eased === 1`. */
  readonly opacity: number;
}

/** `SparkleBurst._scatter` — a radial scatter around a centre point. */
export const SPARKLE_SCATTER: readonly SparkleParticle[] = Object.freeze([
  Object.freeze({ size: 10, dx: -110, dy: -90, opacity: 0.85 }),
  Object.freeze({ size: 8, dx: 100, dy: -100, opacity: 0.7 }),
  Object.freeze({ size: 12, dx: 130, dy: 30, opacity: 0.8 }),
  Object.freeze({ size: 6, dx: -130, dy: 20, opacity: 0.55 }),
  Object.freeze({ size: 8, dx: -90, dy: 110, opacity: 0.65 }),
  Object.freeze({ size: 10, dx: 80, dy: 110, opacity: 0.75 }),
  Object.freeze({ size: 5, dx: 0, dy: -130, opacity: 0.55 }),
  Object.freeze({ size: 5, dx: 0, dy: 130, opacity: 0.5 }),
  Object.freeze({ size: 4, dx: -150, dy: -30, opacity: 0.45 }),
  Object.freeze({ size: 4, dx: 150, dy: -40, opacity: 0.5 }),
  Object.freeze({ size: 3, dx: 60, dy: -70, opacity: 0.4 }),
  Object.freeze({ size: 3, dx: -70, dy: 60, opacity: 0.35 }),
]);

/** `_SparkleStarPainter`'s box: every point below is on a 24-unit grid. */
const STAR_UNITS = 24;

/**
 * `_SparkleStarPainter.paint`'s path, in its own 24-unit coordinates —
 * `moveTo(12, 0)` then seven `lineTo`s, closed. Kept as the raw points so the
 * polygon below is DERIVED rather than a hand-typed percentage list.
 */
export const SPARKLE_STAR_POINTS: readonly (readonly [number, number])[] = Object.freeze([
  Object.freeze([12, 0] as const),
  Object.freeze([14, 10] as const),
  Object.freeze([24, 12] as const),
  Object.freeze([14, 14] as const),
  Object.freeze([12, 24] as const),
  Object.freeze([10, 14] as const),
  Object.freeze([0, 12] as const),
  Object.freeze([10, 10] as const),
]);

/** A 24-unit coordinate as a percentage of the box, trimmed of trailing zeros. */
function unitPercent(value: number): string {
  return `${String(Number(((value / STAR_UNITS) * 100).toFixed(4)))}%`;
}

/**
 * The star as a `clip-path` value. Size-independent by construction: the
 * painter's `s = size / 24` scale factor becomes the percentage itself.
 */
export const SPARKLE_STAR_CLIP_PATH = `polygon(${SPARKLE_STAR_POINTS.map(
  ([x, y]) => `${unitPercent(x)} ${unitPercent(y)}`,
).join(', ')})`;

/** `(index / n) * 0.65` — the fraction of the window the stagger spans. */
export const SPARKLE_STAGGER_SPAN = 0.65;

/** The `0.35` denominator in `localT` — one particle's slice of the window. */
export const SPARKLE_FADE_SPAN = 0.35;

/** `Transform.scale(scale: 0.6 + 0.4 * eased)` starts here. */
export const SPARKLE_START_SCALE = 0.6;

/** How long a single particle's fade runs: 0.35 of the 620ms window. */
export const SPARKLE_FADE_MS = CelebrationTimings.sparkleWindowMs * SPARKLE_FADE_SPAN;

/**
 * When particle `index` of `count` starts its fade, in ms from the burst's own
 * start — `stagger * sparkleWindow`.
 */
export function sparkleDelayMs(index: number, count: number): number {
  if (count <= 0) return 0;
  return (index / count) * SPARKLE_STAGGER_SPAN * CelebrationTimings.sparkleWindowMs;
}
