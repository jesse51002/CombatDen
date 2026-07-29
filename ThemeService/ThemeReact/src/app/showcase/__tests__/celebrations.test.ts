// The celebration primitives (../celebrations/) and the two celebration
// screens' maths (../streakOrbit.ts, and the delay ladders the screens derive).
//
// WHAT IS PINNED HERE IS WHAT A SCREENSHOT CANNOT CATCH. Every one of these is
// a number ported by hand out of Dart, and every one of them fails silently:
//
//  1. THE CURVE SAMPLERS. Flutter's named eases are cubic Béziers, not the
//     analytic twins the web usually reaches for, and the rAF drivers solve
//     them the way `Cubic.transformInternal` does. A wrong solve still animates
//     — just on the wrong curve. So the solver is cross-checked against a
//     brute-force sampling of the same control points.
//  2. THE ORBIT'S PHASE BOUNDARIES. The ring must be at full radius exactly
//     when it stops growing, gone exactly when the icon starts, and the icon
//     gone exactly when the screen hands over. Off-by-a-phase reads as "a bit
//     janky" and is otherwise invisible.
//  3. THE STAR GEOMETRY. The `clip-path` is DERIVED from `_SparkleStarPainter`'s
//     own 24-unit point list; if the derivation drifts the sparkle is still a
//     shape, just not that one.
//  4. THE DELAY LADDERS. Every cascade is `base + <a CelebrationTimings value>`,
//     and a reviewer comparing the two implementations side by side is judging
//     exactly these numbers.
//
// This file lives under src/app/showcase/ rather than src/app/__tests__/ for
// the same reason ./showcaseTokens.test.ts does: eslint Gate 2b forbids
// anything outside the island from importing it.

import { describe, expect, it } from 'vitest';
import { CelebrationTimings } from 'theme-react';

import {
  Curves,
  clamp01,
  cubic,
  phaseProgress,
} from '../celebrations/curves';
import {
  digitCountFor,
  reelOffset,
  reelSpec,
} from '../celebrations/CountUpText';
import {
  FEATURED_SIZE,
  MAX_TILT,
  MIN_SCALE,
  PERSPECTIVE_PX,
  coverFlowTransform,
  wrapIndex,
} from '../celebrations/rewardsCoverFlow';
import {
  SHOWCASE_POINTS_STATS,
  SHOWCASE_REWARDS_STATS,
  SHOWCASE_WINS_STATS,
} from '../celebrations/showcaseCelebrationStats';
import {
  SPARKLE_FADE_MS,
  SPARKLE_SCATTER,
  SPARKLE_STAR_CLIP_PATH,
  SPARKLE_STAR_POINTS,
  sparkleDelayMs,
} from '../celebrations/sparkleGeometry';
import { parseNumeric } from '../celebrations/WinsTile';
import { winsTileDelayMs } from '../celebrations/WinsTileRow';
import { streakBadgeDelayMs } from '../support/StreakWeekStrip';
import {
  DELAY_END_MS,
  ICON_HOLD_END_MS,
  ICON_POP_END_MS,
  ORBIT_COUNT,
  ORBIT_TOTAL_MS,
  RING_END_MS,
  RING_GROW_END_MS,
  SPIN_TURNS,
  STATS_HOLD_MS,
  orbitFrame,
  orbitLayout,
  orbitOffset,
} from '../streakOrbit';
import {
  HEADER_DELAY_MS,
  SUBTITLE_DELAY_MS,
  TILE_BASE_DELAY_MS,
  WINS_HOLD_MS,
} from '../WinsShowcase';
import {
  STRIP_DELAY_MS,
  SUBTITLE_DELAY_MS as STREAK_SUBTITLE_DELAY_MS,
} from '../StatsShowcase';

// ---------------------------------------------------------------------------
// The curve samplers
// ---------------------------------------------------------------------------

/**
 * An independent solve of the same cubic Bézier: walk the curve parameter
 * densely and keep the sample whose x is closest to the target. Slow and dumb
 * on purpose — it shares no code with the subject, so agreement is evidence.
 */
function bruteForceCubic(a: number, b: number, c: number, d: number, x: number): number {
  const axis = (p: number, q: number, m: number): number =>
    3 * p * (1 - m) * (1 - m) * m + 3 * q * (1 - m) * m * m + m * m * m;
  let best = 0;
  let bestError = Number.POSITIVE_INFINITY;
  for (let i = 0; i <= 100000; i++) {
    const m = i / 100000;
    const error = Math.abs(axis(a, c, m) - x);
    if (error < bestError) {
      bestError = error;
      best = m;
    }
  }
  return axis(b, d, best);
}

describe('curves', () => {
  const NAMED: readonly (readonly [string, readonly [number, number, number, number]])[] = [
    ['easeOut', [0.25, 0.1, 0.25, 1]],
    ['easeOutQuart', [0.165, 0.84, 0.44, 1]],
    ['easeInQuart', [0.895, 0.03, 0.685, 0.22]],
    ['easeOutExpo', [0.19, 1, 0.22, 1]],
    ['easeOutBack', [0.175, 0.885, 0.32, 1.275]],
    ['easeInOutCubic', [0.645, 0.045, 0.355, 1]],
  ];

  it('carries Flutter’s own control points, not the analytic twins', () => {
    for (const [name, points] of NAMED) {
      const curve = Curves[name as keyof typeof Curves];
      const [a, b, c, d] = points;
      for (const t of [0.1, 0.25, 0.5, 0.75, 0.9]) {
        // The solver stops at `_cubicErrorBound` (0.001) in X; the resulting Y
        // error is that times the local slope, which none of these exceeds 10x.
        expect(curve(t)).toBeCloseTo(bruteForceCubic(a, b, c, d, t), 1.5);
      }
    }
  });

  it('pins both endpoints EXACTLY — `Curve.transform`’s short-circuit', () => {
    // Not `toBeCloseTo`: the bisection stops within 0.001 of the target x, so
    // without Flutter's short-circuit a not-yet-started phase would already
    // read ~0.005. That is the whole reason the special case exists.
    for (const [name] of NAMED) {
      const curve = Curves[name as keyof typeof Curves];
      expect(curve(0)).toBe(0);
      expect(curve(1)).toBe(1);
    }
  });

  it('clamps out-of-range input rather than extrapolating', () => {
    expect(Curves.easeOutQuart(-5)).toBe(0);
    expect(Curves.easeOutQuart(5)).toBe(1);
    expect(clamp01(-1)).toBe(0);
    expect(clamp01(2)).toBe(1);
    expect(clamp01(0.4)).toBe(0.4);
  });

  it('lets easeOutBack — and ONLY easeOutBack — overshoot 1', () => {
    let backPeak = 0;
    let quartPeak = 0;
    for (let i = 0; i <= 100; i++) {
      backPeak = Math.max(backPeak, Curves.easeOutBack(i / 100));
      quartPeak = Math.max(quartPeak, Curves.easeOutQuart(i / 100));
    }
    expect(backPeak).toBeGreaterThan(1);
    expect(quartPeak).toBeLessThanOrEqual(1.001);
  });

  it('is monotonic where Flutter’s curve is', () => {
    let previous = -1;
    for (let i = 0; i <= 200; i++) {
      const value = Curves.easeOutQuart(i / 200);
      expect(value).toBeGreaterThanOrEqual(previous - 1e-6);
      previous = value;
    }
  });

  it('builds an arbitrary Cubic the same way', () => {
    const linear = cubic(1 / 3, 1 / 3, 2 / 3, 2 / 3);
    expect(linear(0.4)).toBeCloseTo(0.4, 2);
  });
});

describe('phaseProgress', () => {
  it('is the Dart’s `((t - from) / (to - from)).clamp(0, 1)`', () => {
    expect(phaseProgress(500, 500, 1100)).toBe(0);
    expect(phaseProgress(800, 500, 1100)).toBeCloseTo(0.5, 6);
    expect(phaseProgress(1100, 500, 1100)).toBe(1);
    expect(phaseProgress(0, 500, 1100)).toBe(0);
    expect(phaseProgress(5000, 500, 1100)).toBe(1);
  });

  it('treats a zero-length phase as already over', () => {
    expect(phaseProgress(100, 100, 100)).toBe(1);
    expect(phaseProgress(99, 100, 100)).toBe(0);
  });
});

// ---------------------------------------------------------------------------
// The sparkle burst
// ---------------------------------------------------------------------------

describe('sparkle geometry', () => {
  it('derives the 8-point star from `_SparkleStarPainter`’s own path', () => {
    expect(SPARKLE_STAR_POINTS).toHaveLength(8);
    // `moveTo(12 * s, 0)` … `lineTo(10 * s, 10 * s)` … `close()`.
    expect(SPARKLE_STAR_POINTS[0]).toEqual([12, 0]);
    expect(SPARKLE_STAR_POINTS[4]).toEqual([12, 24]);
    expect(SPARKLE_STAR_CLIP_PATH).toBe(
      'polygon(50% 0%, 58.3333% 41.6667%, 100% 50%, 58.3333% 58.3333%, ' +
        '50% 100%, 41.6667% 58.3333%, 0% 50%, 41.6667% 41.6667%)',
    );
  });

  it('is size-independent — the painter’s `s = size / 24` becomes the percent', () => {
    // Every coordinate resolves to its share of the box, so one class scales
    // from the 3px particles to the 12px one with no per-size geometry.
    expect(SPARKLE_STAR_CLIP_PATH).not.toContain('px');
  });

  it('carries `_scatter` verbatim — twelve particles', () => {
    expect(SPARKLE_SCATTER).toHaveLength(12);
    expect(SPARKLE_SCATTER[0]).toEqual({ size: 10, dx: -110, dy: -90, opacity: 0.85 });
    expect(SPARKLE_SCATTER[11]).toEqual({ size: 3, dx: -70, dy: 60, opacity: 0.35 });
  });

  it('slices the window into a per-particle delay and a fixed fade', () => {
    // stagger = (index / n) * 0.65, in wall clock against the 620ms window.
    expect(sparkleDelayMs(0, 12)).toBe(0);
    expect(sparkleDelayMs(6, 12)).toBeCloseTo(0.5 * 0.65 * 620, 6);
    expect(sparkleDelayMs(11, 12)).toBeCloseTo((11 / 12) * 0.65 * 620, 6);
    // localT's 0.35 denominator, NOT `sparkleFadeMs` (220) — see the module.
    expect(SPARKLE_FADE_MS).toBeCloseTo(217, 6);
  });

  it('finishes the last particle inside the window it was sliced from', () => {
    const last = sparkleDelayMs(SPARKLE_SCATTER.length - 1, SPARKLE_SCATTER.length);
    expect(last + SPARKLE_FADE_MS).toBeLessThanOrEqual(CelebrationTimings.sparkleWindowMs);
  });
});

// ---------------------------------------------------------------------------
// The count-up odometer
// ---------------------------------------------------------------------------

describe('count-up reels', () => {
  it('ports `_digitCountFor`', () => {
    expect(digitCountFor(0)).toBe(1);
    expect(digitCountFor(3)).toBe(1);
    expect(digitCountFor(9)).toBe(1);
    expect(digitCountFor(10)).toBe(2);
    expect(digitCountFor(160)).toBe(3);
    expect(digitCountFor(3400)).toBe(4);
  });

  it('ports `_divisor` / `_maxIndex` per position', () => {
    expect(reelSpec(160, 0)).toEqual({ divisor: 1, maxIndex: 160 });
    expect(reelSpec(160, 1)).toEqual({ divisor: 10, maxIndex: 16 });
    expect(reelSpec(160, 2)).toEqual({ divisor: 100, maxIndex: 1 });
  });

  it('lands every position on the right digit, because the last cell IS it', () => {
    for (const target of [3, 28, 160, 3400]) {
      const digits = String(target).split('').reverse();
      for (let p = 0; p < digitCountFor(target); p++) {
        const { divisor, maxIndex } = reelSpec(target, p);
        // The strip renders `i % 10`, so the settled cell shows this.
        expect(maxIndex % 10).toBe(Number(digits[p]));
        expect(reelOffset(1, target, divisor, maxIndex)).toBe(maxIndex);
      }
    }
  });

  it('clamps a position that would over-roll — Dart’s `.clamp(0, maxIndex)`', () => {
    // 160 / 100 = 1.6, but the hundreds reel only has cells 0 and 1.
    expect(reelOffset(1, 160, 100, 1)).toBe(1);
    expect(reelOffset(0.5, 160, 100, 1)).toBeCloseTo(0.8, 6);
    expect(reelOffset(0, 160, 1, 160)).toBe(0);
    expect(reelOffset(0.5, 160, 1, 160)).toBeCloseTo(80, 6);
  });
});

describe('parseNumeric', () => {
  it('rolls a clean integer', () => {
    expect(parseNumeric('160')).toEqual({ prefix: '', value: 160 });
    expect(parseNumeric('+160')).toEqual({ prefix: '+', value: 160 });
    expect(parseNumeric('-3')).toEqual({ prefix: '-', value: 3 });
    expect(parseNumeric('  28  ')).toEqual({ prefix: '', value: 28 });
  });

  it('leaves anything else as static text — Dart returns null', () => {
    expect(parseNumeric('3 week')).toBeNull();
    expect(parseNumeric('')).toBeNull();
    expect(parseNumeric('1.5')).toBeNull();
    expect(parseNumeric('3.4k')).toBeNull();
  });

  it('agrees with the wins tiles it was written for', () => {
    const [streak, rank, points] = SHOWCASE_WINS_STATS.tiles;
    expect(parseNumeric(streak?.value ?? '')).toBeNull();
    expect(parseNumeric(rank?.value ?? '')).toEqual({ prefix: '', value: 28 });
    expect(parseNumeric(points?.value ?? '')).toEqual({ prefix: '+', value: 160 });
  });
});

// ---------------------------------------------------------------------------
// The cascades
// ---------------------------------------------------------------------------

describe('the wins cascade', () => {
  it('derives every beat from CelebrationTimings, not from a literal', () => {
    expect(HEADER_DELAY_MS).toBe(CelebrationTimings.revealStaggerMs);
    expect(SUBTITLE_DELAY_MS).toBe(CelebrationTimings.revealStaggerMs * 2);
    // The tiles start once the subtitle has LANDED, not when it started.
    expect(TILE_BASE_DELAY_MS).toBe(SUBTITLE_DELAY_MS + CelebrationTimings.revealMs);
    expect(TILE_BASE_DELAY_MS).toBe(440);
  });

  it('cascades the three tiles at DOUBLE the badge stagger', () => {
    expect(winsTileDelayMs(TILE_BASE_DELAY_MS, 0)).toBe(440);
    expect(winsTileDelayMs(TILE_BASE_DELAY_MS, 1)).toBe(580);
    expect(winsTileDelayMs(TILE_BASE_DELAY_MS, 2)).toBe(720);
  });

  it('holds the finished recap long enough to read it', () => {
    expect(WINS_HOLD_MS).toBe(3200);
    // The last tile must have landed well before the loop restarts.
    expect(winsTileDelayMs(TILE_BASE_DELAY_MS, 2) + CelebrationTimings.revealMs).toBeLessThan(
      WINS_HOLD_MS,
    );
  });
});

describe('the streak cascade', () => {
  it('waits out the whole count-up before the caption', () => {
    expect(STREAK_SUBTITLE_DELAY_MS).toBe(CelebrationTimings.countUpMs);
    expect(STRIP_DELAY_MS).toBe(CelebrationTimings.countUpMs + CelebrationTimings.revealStaggerMs);
    expect(STRIP_DELAY_MS).toBe(1490);
  });

  it('cascades the seven day badges at the single badge stagger', () => {
    expect(streakBadgeDelayMs(STRIP_DELAY_MS, 0)).toBe(1490);
    expect(streakBadgeDelayMs(STRIP_DELAY_MS, 6)).toBe(1490 + 70 * 6);
  });

  it('holds the statement long enough for the strip to finish landing', () => {
    const lastBadge = streakBadgeDelayMs(STRIP_DELAY_MS, 6) + CelebrationTimings.revealMs;
    expect(lastBadge).toBeLessThan(STATS_HOLD_MS);
  });
});

// ---------------------------------------------------------------------------
// The orbit ring
// ---------------------------------------------------------------------------

describe('orbit layout', () => {
  // The showcase body on a 390x844 phone: 390 - 2 * screenHorizontalPadding
  // wide, and 844 - the frame's 52pt status inset tall.
  const WIDTH = 358;
  const HEIGHT = 792;

  it('scales off the SMALLER extent, as `LayoutBuilder` does', () => {
    const layout = orbitLayout(WIDTH, HEIGHT);
    expect(layout.renderScale).toBeCloseTo(358 / 280, 6);
    expect(layout.orbitSize).toBeCloseTo(30 * (358 / 280), 6);
    expect(layout.iconSize).toBeCloseTo(120 * (358 / 280), 6);
    // smallerExtent / 2 - edgePad - orbitSize / 2.
    expect(layout.maxRadius).toBeCloseTo(179 - 28 - (30 * (358 / 280)) / 2, 6);
  });

  it('keeps the whole ring inside the box it measured', () => {
    const layout = orbitLayout(WIDTH, HEIGHT);
    expect(layout.maxRadius + layout.orbitSize / 2).toBeLessThanOrEqual(WIDTH / 2);
  });

  it('is square-agnostic — a tall box scales off its width', () => {
    expect(orbitLayout(200, 900).renderScale).toBeCloseTo(200 / 280, 6);
    expect(orbitLayout(900, 200).renderScale).toBeCloseTo(200 / 280, 6);
  });
});

describe('orbit phases', () => {
  const R = 131.82;

  it('sums the six phases into the controller’s duration', () => {
    expect(ORBIT_TOTAL_MS).toBe(500 + 600 + 500 + 400 + 800 + 250);
    expect(ORBIT_TOTAL_MS).toBe(3050);
    expect(DELAY_END_MS).toBe(500);
    expect(RING_GROW_END_MS).toBe(1100);
    expect(RING_END_MS).toBe(1600);
    expect(ICON_POP_END_MS).toBe(2000);
    expect(ICON_HOLD_END_MS).toBe(2800);
  });

  it('shows nothing through the opening delay', () => {
    for (const e of [0, 250, DELAY_END_MS]) {
      const f = orbitFrame(e, R);
      expect(f.radiusFactor).toBeCloseTo(0, 6);
      expect(f.radius).toBeCloseTo(0, 6);
      expect(f.iconOpacity).toBeCloseTo(0, 6);
    }
  });

  it('has the ring at FULL radius exactly when it stops growing', () => {
    const f = orbitFrame(RING_GROW_END_MS, R);
    expect(f.radiusFactor).toBeCloseTo(1, 2);
    expect(f.radius).toBeCloseTo(R, 1);
  });

  it('has the ring GONE exactly when the big icon starts', () => {
    const f = orbitFrame(RING_END_MS, R);
    expect(f.radiusFactor).toBeCloseTo(0, 2);
    // …and the icon has not started yet, so the two never share the screen.
    expect(f.iconOpacity).toBeCloseTo(0, 2);
    expect(f.iconScale).toBeCloseTo(0, 2);
  });

  it('overshoots the icon’s pop — that is what easeOutBack is for', () => {
    let peak = 0;
    for (let e = RING_END_MS; e <= ICON_POP_END_MS; e += 5) {
      peak = Math.max(peak, orbitFrame(e, R).iconScale);
    }
    expect(peak).toBeGreaterThan(1);
    // …and settles back to exactly 1 for the hold.
    expect(orbitFrame(ICON_POP_END_MS, R).iconScale).toBeCloseTo(1, 2);
    expect(orbitFrame(ICON_HOLD_END_MS, R).iconScale).toBeCloseTo(1, 2);
  });

  it('holds the icon fully opaque between the pop and the exit', () => {
    for (const e of [ICON_POP_END_MS, 2400, ICON_HOLD_END_MS]) {
      expect(orbitFrame(e, R).iconOpacity).toBeCloseTo(1, 2);
    }
  });

  it('ends invisible, so the hand-over to the stats view has nothing to hide', () => {
    const f = orbitFrame(ORBIT_TOTAL_MS, R);
    expect(f.iconOpacity).toBeCloseTo(0, 2);
    // `1 - 0.3 * iconExitE` — it shrinks by 30% as it goes.
    expect(f.iconScale).toBeCloseTo(0.7, 2);
    expect(f.radiusFactor).toBeCloseTo(0, 6);
  });

  it('clamps past the end rather than running on', () => {
    expect(orbitFrame(99999, R)).toEqual(orbitFrame(ORBIT_TOTAL_MS, R));
    expect(orbitFrame(-100, R)).toEqual(orbitFrame(0, R));
  });

  it('spins 1.6 turns across the WHOLE timeline, not just the ring’s phases', () => {
    expect(orbitFrame(0, R).spin).toBeCloseTo(0, 6);
    expect(orbitFrame(ORBIT_TOTAL_MS, R).spin).toBeCloseTo(2 * Math.PI * SPIN_TURNS, 6);
    expect(orbitFrame(ORBIT_TOTAL_MS / 2, R).spin).toBeCloseTo(Math.PI * SPIN_TURNS, 6);
  });
});

describe('orbit offsets', () => {
  it('spaces the eight icons evenly around the circle', () => {
    const radius = 100;
    for (let i = 0; i < ORBIT_COUNT; i++) {
      const { x, y } = orbitOffset(i, 0, radius);
      expect(Math.hypot(x, y)).toBeCloseTo(radius, 6);
    }
    expect(orbitOffset(0, 0, radius).x).toBeCloseTo(radius, 6);
    expect(orbitOffset(0, 0, radius).y).toBeCloseTo(0, 6);
    // A quarter turn round the ring is two of eight slots.
    expect(orbitOffset(2, 0, radius).x).toBeCloseTo(0, 6);
    expect(orbitOffset(2, 0, radius).y).toBeCloseTo(radius, 6);
  });

  it('rotates the whole ring with the spin, keeping the spacing', () => {
    const spun = orbitOffset(0, Math.PI / 2, 100);
    expect(spun.x).toBeCloseTo(0, 6);
    expect(spun.y).toBeCloseTo(100, 6);
  });

  it('collapses to the centre when the radius does', () => {
    for (let i = 0; i < ORBIT_COUNT; i++) {
      const { x, y } = orbitOffset(i, 1.234, 0);
      // `toBeCloseTo`, not `toEqual`: `cos(theta) * 0` is signed in JS, and a
      // -0 offset is the same pixel as a +0 one.
      expect(x).toBeCloseTo(0, 12);
      expect(y).toBeCloseTo(0, 12);
    }
  });
});

// ---------------------------------------------------------------------------
// The rewards cover flow
// ---------------------------------------------------------------------------

describe('cover flow', () => {
  it('leaves the active page face-on at full size', () => {
    expect(coverFlowTransform(0)).toEqual({ scale: 1, tiltRadians: -0 });
  });

  it('shrinks and tilts a neighbour to the limit', () => {
    expect(coverFlowTransform(1)).toEqual({ scale: MIN_SCALE, tiltRadians: -MAX_TILT });
    expect(coverFlowTransform(-1)).toEqual({ scale: MIN_SCALE, tiltRadians: MAX_TILT });
  });

  it('clamps beyond one slot — a far page looks the same as a near one', () => {
    expect(coverFlowTransform(4)).toEqual(coverFlowTransform(1));
    expect(coverFlowTransform(-9)).toEqual(coverFlowTransform(-1));
  });

  it('interpolates linearly between them, as `1 - (1 - minScale) * t` does', () => {
    const half = coverFlowTransform(0.5);
    expect(half.scale).toBeCloseTo(1 - (1 - MIN_SCALE) * 0.5, 6);
    expect(half.tiltRadians).toBeCloseTo(-MAX_TILT * 0.5, 6);
  });

  it('turns Flutter’s `setEntry(3, 2, 0.0015)` into a CSS perspective DISTANCE', () => {
    expect(PERSPECTIVE_PX).toBeCloseTo(1 / 0.0015, 6);
    expect(FEATURED_SIZE).toBe(208);
  });

  it('wraps a page index the way Dart’s `%` does, not JS’s', () => {
    expect(wrapIndex(0, 3)).toBe(0);
    expect(wrapIndex(4, 3)).toBe(1);
    expect(wrapIndex(10001, 3)).toBe(wrapIndex(10001 % 3, 3));
    // JS would answer -1 here and index off the end of the list.
    expect(wrapIndex(-1, 3)).toBe(2);
    expect(wrapIndex(-4, 3)).toBe(2);
    expect(wrapIndex(1, 0)).toBe(0);
  });
});

// ---------------------------------------------------------------------------
// The ported data
// ---------------------------------------------------------------------------

describe('celebration stats', () => {
  it('is the Dart’s const data, verbatim', () => {
    expect(SHOWCASE_WINS_STATS.title).toBe('Today’s wins');
    expect(SHOWCASE_WINS_STATS.heroAsset).toBe('stat_wins_trophy.png');
    expect(SHOWCASE_WINS_STATS.tiles).toHaveLength(3);
    expect(SHOWCASE_POINTS_STATS).toEqual({ gained: 160, totalPoints: 3400 });
    expect(SHOWCASE_REWARDS_STATS.items).toHaveLength(3);
  });

  it('features an item the carousel can actually centre on', () => {
    expect(SHOWCASE_REWARDS_STATS.featuredIndex).toBeGreaterThanOrEqual(0);
    expect(SHOWCASE_REWARDS_STATS.featuredIndex).toBeLessThan(SHOWCASE_REWARDS_STATS.items.length);
  });
});
