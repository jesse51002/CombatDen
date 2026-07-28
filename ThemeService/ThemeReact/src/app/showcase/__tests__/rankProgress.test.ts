// The pure half of the Profile screen (../profile/mockRankProgress.ts) and the
// next-rank arithmetic (../profile/NextRankSection.tsx), which port
// `MobileApp/lib/features/profile/data/rank_progress_selectors.dart`,
// `_RatingGraphPainter` and `NextRankSection.build`.
//
// The graph path is the piece worth pinning hardest: it is the only place in
// this island where a Flutter `CustomPainter`'s arithmetic was retyped as SVG,
// so a drift there is invisible in review and obvious on screen.

import { describe, expect, it } from 'vitest';

import { nextRankProgress } from '../profile/NextRankSection';
import type { ShowcaseRankPoint } from '../profile/mockRankProgress';
import {
  RANK_TIMEFRAMES,
  SHOWCASE_RANK,
  SHOWCASE_RANK_POINTS,
  plottableSeries,
  ratingGraphPath,
  windowPoints,
} from '../profile/mockRankProgress';

function point(date: string, into: number, needed = 24): ShowcaseRankPoint {
  return { date, classesIntoRank: into, classesNeeded: needed };
}

describe('plottableSeries', () => {
  it('normalises classes-into-rank against the per-step threshold', () => {
    expect(plottableSeries([point('2026-01-01', 12)])).toEqual([0.5]);
  });

  it('clamps above the threshold rather than plotting off the top', () => {
    expect(plottableSeries([point('2026-01-01', 30)])).toEqual([1]);
  });

  it('maps a non-positive threshold to 0 instead of dividing by zero', () => {
    expect(plottableSeries([point('2026-01-01', 5, 0)])).toEqual([0]);
    expect(plottableSeries([point('2026-01-01', 5, -1)])).toEqual([0]);
  });
});

describe('windowPoints', () => {
  const points = [
    point('2026-01-01', 1),
    point('2026-05-01', 2),
    point('2026-05-15', 3),
    point('2026-05-19', 4),
  ];

  it('returns the series untouched for ALL', () => {
    const all = RANK_TIMEFRAMES[RANK_TIMEFRAMES.length - 1];
    expect(all?.days).toBeNull();
    expect(windowPoints(points, { label: 'ALL', days: null })).toEqual(points);
  });

  it('anchors at the LATEST point, not at today', () => {
    // The whole reason the anchor is the last point: a member who last trained
    // months ago must still see their real recent history, not an empty 1W.
    expect(windowPoints(points, { label: '1W', days: 7 }).map((p) => p.date)).toEqual([
      '2026-05-15',
      '2026-05-19',
    ]);
  });

  it('keeps unparseable dates — never hide real data', () => {
    const withJunk = [point('not-a-date', 9), ...points];
    expect(windowPoints(withJunk, { label: '1W', days: 7 })[0]?.date).toBe('not-a-date');
  });

  it('is a no-op on an empty series', () => {
    expect(windowPoints([], { label: '1M', days: 30 })).toEqual([]);
  });
});

describe('ratingGraphPath', () => {
  it('returns nothing for a series the painter would also refuse to draw', () => {
    expect(ratingGraphPath([], 393, 196.5)).toBe('');
    expect(ratingGraphPath([0.5], 393, 196.5)).toBe('');
  });

  it('starts at the first sample and ends at the last, spaced across the width', () => {
    const d = ratingGraphPath([0, 1], 100, 200);
    // y is inverted: 0 sits at the bottom (y = height), 1 at the top (y = 0).
    expect(d.startsWith('M 0 200')).toBe(true);
    expect(d.endsWith('100 0')).toBe(true);
  });

  it('emits one cubic per gap between samples', () => {
    const d = ratingGraphPath([0, 0.5, 1, 0.25], 300, 100);
    expect(d.split(' C ')).toHaveLength(4); // 1 move-to head + 3 segments
  });

  it('duplicates the endpoints, which is what stops the curve overshooting', () => {
    // The painter's own `p0 = points[0]` / `p3 = points[i + 1]` at the ends.
    // A straight ramp is the test that proves it: every control point below
    // satisfies the line y = 100 - x/2, so the curve is the segment itself. Drop
    // either duplication and the ends bow away from it.
    const d = ratingGraphPath([0, 0.5, 1], 200, 100);
    expect(d).toBe(
      'M 0 100 C 16.667 91.667, 66.667 66.667, 100 50 C 133.333 33.333, 183.333 8.333, 200 0',
    );

    // Stated as the property, so a future width/height change does not need the
    // magic string above recomputed by hand to stay meaningful.
    const coords = [...d.matchAll(/(-?\d+(?:\.\d+)?) (-?\d+(?:\.\d+)?)/g)];
    expect(coords).toHaveLength(7);
    for (const [, x, y] of coords) {
      expect(Number(y)).toBeCloseTo(100 - Number(x) / 2, 2);
    }
  });

  it('clamps an out-of-range sample into the box', () => {
    const d = ratingGraphPath([-1, 2], 100, 200);
    expect(d.startsWith('M 0 200')).toBe(true);
    expect(d.endsWith('100 0')).toBe(true);
  });
});

describe('nextRankProgress', () => {
  it('reads the fraction of the step the member has done', () => {
    expect(nextRankProgress({ name: 'Blue', classesTillNextStep: 24, classesSinceRank: 12 })).toEqual(
      { progress: 0.5, label: '12 / 24 classes' },
    );
  });

  it('names the top of the ladder instead of printing a divide by zero', () => {
    expect(nextRankProgress({ name: 'Black', classesTillNextStep: 0, classesSinceRank: 40 })).toEqual(
      { progress: 0, label: 'Top of the ladder.' },
    );
  });

  it('clamps a member who has overshot the threshold', () => {
    expect(
      nextRankProgress({ name: 'Blue', classesTillNextStep: 10, classesSinceRank: 40 }).progress,
    ).toBe(1);
  });
});

describe('the bundled profile series', () => {
  it('plots a sawtooth — the shape a promotion actually produces', () => {
    const series = plottableSeries(SHOWCASE_RANK_POINTS);
    // At least two resets: a value strictly lower than the one before it.
    const resets = series.filter((value, i) => i > 0 && value < (series[i - 1] ?? 0));
    expect(resets.length).toBeGreaterThanOrEqual(2);
  });

  it('stays inside the plot box at every sample', () => {
    for (const value of plottableSeries(SHOWCASE_RANK_POINTS)) {
      expect(value).toBeGreaterThanOrEqual(0);
      expect(value).toBeLessThanOrEqual(1);
    }
  });

  it('shares one threshold with the rank the badge reads', () => {
    for (const item of SHOWCASE_RANK_POINTS) {
      expect(item.classesNeeded).toBe(SHOWCASE_RANK.classesTillNextStep);
    }
  });

  it('is long enough to draw, and windows down to a real 1W', () => {
    expect(SHOWCASE_RANK_POINTS.length).toBeGreaterThanOrEqual(2);
    expect(windowPoints(SHOWCASE_RANK_POINTS, { label: '1W', days: 7 }).length).toBeGreaterThan(0);
  });
});
