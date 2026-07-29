// The pure half of ./SparkleHero.tsx, which ports
// ../../../../../../CRM/lib/showcase/rewards/sparkle_hero.dart.
//
// Two things live here because neither is a component and both are worth
// pinning in a test: the SCATTER and the CLOCK.
//
// THE SCATTER is `_kSparkles` verbatim — twenty-two `(size, dx, dy, opacity)`
// tuples ringing the "YOU EARNED / 3,400 / POINTS" block. Its order in the list
// is NOT its order on screen: `_orderByDistance` sorts the indices by squared
// distance from the centre, and that RANK is what the stagger below is computed
// from, so the sparkles light up outward from the number rather than in
// list order.
//
// THE CLOCK. One controller over `CelebrationTimings.sparkleWindow`, sliced per
// sparkle:
//
//   stagger = (rank / n) * 0.7        where this sparkle's fade STARTS
//   localT  = ((t - stagger) / 0.35)  how long that fade LASTS
//
// Both are fractions of the window, so they port as a wall-clock delay and a
// wall-clock duration and the whole hero becomes 23 CSS animations with nothing
// left in JS — the same shape ../celebrations/sparkleGeometry.ts takes, with a
// wider stagger span (0.7 vs 0.65) because there are nearly twice as many.
//
// THE STAR SHAPE IS NOT DUPLICATED HERE. `_SparklePainter` in this Dart file
// walks the identical eight points as `sparkle_burst.dart`'s
// `_SparkleStarPainter`, so ./SparkleHero.tsx reads
// `SPARKLE_STAR_CLIP_PATH` from ../celebrations/sparkleGeometry.ts rather than
// deriving a second copy of the same polygon.

import { CelebrationTimings } from 'theme-react';

/** One entry of `_kSparkles`: `(size, dx, dy, opacity)`. */
export interface HeroSparkle {
  /** Edge length of the star's box, in px. */
  readonly size: number;
  /** Offset from the hero's centre, in px. */
  readonly dx: number;
  readonly dy: number;
  /** The opacity it settles at — `eased * s.$4` at `eased === 1`. */
  readonly opacity: number;
}

/** `_kSparkles`, in the Dart's own list order. */
export const HERO_SPARKLES: readonly HeroSparkle[] = Object.freeze([
  Object.freeze({ size: 14, dx: -150, dy: -40, opacity: 0.85 }),
  Object.freeze({ size: 12, dx: 156, dy: 36, opacity: 0.8 }),
  Object.freeze({ size: 10, dx: 152, dy: -48, opacity: 0.6 }),
  Object.freeze({ size: 10, dx: -156, dy: 28, opacity: 0.55 }),
  Object.freeze({ size: 8, dx: -170, dy: -8, opacity: 0.55 }),
  Object.freeze({ size: 8, dx: 168, dy: -16, opacity: 0.65 }),
  Object.freeze({ size: 8, dx: 0, dy: -62, opacity: 0.5 }),
  Object.freeze({ size: 8, dx: -70, dy: 60, opacity: 0.55 }),
  Object.freeze({ size: 8, dx: 76, dy: 62, opacity: 0.6 }),
  Object.freeze({ size: 6, dx: 110, dy: -38, opacity: 0.45 }),
  Object.freeze({ size: 6, dx: -116, dy: -50, opacity: 0.4 }),
  Object.freeze({ size: 6, dx: 130, dy: 8, opacity: 0.55 }),
  Object.freeze({ size: 6, dx: -128, dy: 60, opacity: 0.45 }),
  Object.freeze({ size: 6, dx: 172, dy: 22, opacity: 0.55 }),
  Object.freeze({ size: 4, dx: 50, dy: -48, opacity: 0.4 }),
  Object.freeze({ size: 4, dx: -56, dy: 38, opacity: 0.4 }),
  Object.freeze({ size: 4, dx: 140, dy: -30, opacity: 0.45 }),
  Object.freeze({ size: 4, dx: -148, dy: -28, opacity: 0.4 }),
  Object.freeze({ size: 4, dx: 24, dy: 70, opacity: 0.45 }),
  Object.freeze({ size: 3, dx: 96, dy: -58, opacity: 0.35 }),
  Object.freeze({ size: 3, dx: -100, dy: 18, opacity: 0.35 }),
  Object.freeze({ size: 3, dx: 0, dy: 78, opacity: 0.4 }),
]);

/** `(rank / n) * 0.7` — the fraction of the window the stagger spans. */
export const HERO_STAGGER_SPAN = 0.7;

/** The `0.35` denominator in `localT` — one sparkle's slice of the window. */
export const HERO_FADE_SPAN = 0.35;

/** `Transform.scale(scale: 0.5 + 0.5 * eased)` starts here. */
export const HERO_START_SCALE = 0.5;

/** `Transform.scale(scale: 0.92 + 0.08 * t)` — the accent block's own entrance. */
export const ACCENT_START_SCALE = 0.92;

/** How long a single sparkle's fade runs: 0.35 of the 620ms window. */
export const HERO_FADE_MS = CelebrationTimings.sparkleWindowMs * HERO_FADE_SPAN;

/**
 * `_orderByDistance` — the sparkle indices sorted by squared distance from the
 * centre, nearest first. The RANK in this list, not the list index, is what
 * `_animatedSparkle` staggers on, so the scatter lights up outward.
 *
 * Both languages sort stably at this size (Dart's `List.sort` is an insertion
 * sort below 32 elements; `Array.prototype.sort` is stable since ES2019), so
 * ties keep their list order in the port exactly as they do in the Dart.
 */
export function orderByDistance(sparkles: readonly HeroSparkle[]): readonly number[] {
  const indices = sparkles.map((_, index) => index);
  indices.sort((a, b) => {
    const first = sparkles[a];
    const second = sparkles[b];
    if (first === undefined || second === undefined) return 0;
    return first.dx * first.dx + first.dy * first.dy - (second.dx * second.dx + second.dy * second.dy);
  });
  return indices;
}

/**
 * When the sparkle at `rank` of `count` starts its fade, in ms from the hero's
 * own start — `stagger * sparkleWindow`.
 */
export function heroSparkleDelayMs(rank: number, count: number): number {
  if (count <= 0) return 0;
  return (rank / count) * HERO_STAGGER_SPAN * CelebrationTimings.sparkleWindowMs;
}
