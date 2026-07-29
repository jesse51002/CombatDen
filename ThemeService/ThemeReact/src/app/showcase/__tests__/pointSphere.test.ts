// Pins the pure half of PointsShowcase — the port of
// CRM/lib/showcase/points_showcase.dart's `_PointSphereState`.
//
// Every failure mode here is invisible in a screenshot: a lattice that drifts,
// a converge that starts a beat early, a depth sort running backwards, or a
// fade reading the raw converge instead of the eased one. A still frame of
// fourteen stars looks plausible in all four cases.

import { describe, expect, it } from 'vitest';

import {
  CONVERGE_START,
  EDGE_PAD,
  GOLDEN_ANGLE,
  REFERENCE_EXTENT,
  SPHERE_MS,
  SPIN_TURNS,
  STAR_COUNT,
  STAR_SEEDS,
  STAR_SIZES,
  sphereFrame,
  sphereLayout,
  starSize,
} from '../pointSphere';

describe('the seeded lattice', () => {
  it('seeds exactly _kStarCount stars', () => {
    expect(STAR_SEEDS).toHaveLength(STAR_COUNT);
  });

  it('puts every star ON the unit sphere', () => {
    for (const s of STAR_SEEDS) {
      const r = Math.sqrt(s.x * s.x + s.y * s.y + s.z * s.z);
      expect(r).toBeCloseTo(1, 10);
    }
  });

  it('steps y evenly down the axis, never reaching either pole', () => {
    const ys = STAR_SEEDS.map((s) => s.y);
    // Strictly descending — `1 - 2(i + 0.5)/count`.
    for (let i = 1; i < ys.length; i++) {
      expect(ys[i]!).toBeLessThan(ys[i - 1]!);
    }
    // The 0.5 offset is what keeps a star off each pole; without it the first
    // and last stars sit exactly at y = ±1 with zero ring radius, i.e. two
    // stars stacked dead centre.
    expect(Math.abs(ys[0]!)).toBeLessThan(1);
    expect(Math.abs(ys[ys.length - 1]!)).toBeLessThan(1);
  });

  it('advances theta by the golden angle so no two stars share a meridian', () => {
    // Recomputing the angle from x/z proves the seed used GOLDEN_ANGLE rather
    // than an even division, which would line the stars up into visible spokes.
    const theta = (s: (typeof STAR_SEEDS)[number]) => Math.atan2(s.z, s.x);
    const first = theta(STAR_SEEDS[0]!);
    const second = theta(STAR_SEEDS[1]!);
    const delta = ((second - first) % (2 * Math.PI)) + 2 * Math.PI;
    expect(delta % (2 * Math.PI)).toBeCloseTo(GOLDEN_ANGLE % (2 * Math.PI), 4);
  });

  it('uses the Dart literal, not pi * (3 - sqrt(5))', () => {
    // They differ in the sixth decimal, and after thirteen multiplications
    // that is a visibly rotated lattice.
    expect(GOLDEN_ANGLE).toBe(2.39996);
    expect(GOLDEN_ANGLE).not.toBe(Math.PI * (3 - Math.sqrt(5)));
  });

  it('cycles the size table', () => {
    for (let i = 0; i < STAR_COUNT; i++) {
      expect(STAR_SEEDS[i]!.size).toBe(STAR_SIZES[i % STAR_SIZES.length]);
    }
  });
});

describe('sphereLayout', () => {
  it('scales the art off the SMALLER extent', () => {
    // A tall box must not produce gigantic stars.
    const tall = sphereLayout(280, 840);
    expect(tall.renderScale).toBe(1);
    const wide = sphereLayout(840, 280);
    expect(wide.renderScale).toBe(1);
  });

  it('derives renderScale from the reference extent', () => {
    const half = sphereLayout(REFERENCE_EXTENT / 2, REFERENCE_EXTENT / 2);
    expect(half.renderScale).toBe(0.5);
    expect(half.edgePad).toBe(EDGE_PAD * 0.5);
  });

  it('halves each axis independently, which is what makes it an ellipsoid', () => {
    const l = sphereLayout(300, 500);
    expect(l.halfWidth).toBe(150);
    expect(l.halfHeight).toBe(250);
  });
});

describe('starSize', () => {
  it('scales a seed size by renderScale', () => {
    expect(starSize(0, 1)).toBe(STAR_SEEDS[0]!.size);
    expect(starSize(0, 0.5)).toBe(STAR_SEEDS[0]!.size * 0.5);
  });

  it('returns 0 for an out-of-range index rather than throwing', () => {
    expect(starSize(999, 1)).toBe(0);
  });
});

describe('sphereFrame', () => {
  const layout = sphereLayout(280, 280);

  it('returns every star, in paint order back to front', () => {
    const frame = sphereFrame(0, layout);
    expect(frame).toHaveLength(STAR_COUNT);
    frame.forEach((s, i) => expect(s.order).toBe(i));
    // Depth drives scale, and the frame is sorted by depth, so scale must be
    // non-decreasing across the paint order. A reversed sort inverts this.
    for (let i = 1; i < frame.length; i++) {
      expect(frame[i]!.scale).toBeGreaterThanOrEqual(frame[i - 1]!.scale - 1e-12);
    }
  });

  it('paints every seed exactly once', () => {
    const indices = sphereFrame(400, layout).map((s) => s.index).sort((a, b) => a - b);
    expect(indices).toEqual([...Array(STAR_COUNT).keys()]);
  });

  it('holds full spread until the converge point', () => {
    const justBefore = sphereFrame(SPHERE_MS * CONVERGE_START - 1, layout);
    // Nothing has collapsed yet: the widest star is still out near the edge.
    const spread = Math.max(...justBefore.map((s) => Math.abs(s.dx)));
    expect(spread).toBeGreaterThan(0);
    // And nothing has begun to fade. Peak opacity is NOT a fixed number to
    // compare against — the lattice has spun, so a different star is frontmost
    // with a slightly different depth. What holds while converge is zero is the
    // RANGE: opacity is (1 - 0) * (0.4 + 0.6 * depth), so every star sits in
    // [0.4, 1] and scale in [0.55, 1]. Any fade collapses both floors.
    for (const s of justBefore) {
      expect(s.opacity).toBeGreaterThanOrEqual(0.4 - 1e-9);
      expect(s.opacity).toBeLessThanOrEqual(1 + 1e-9);
      expect(s.scale).toBeGreaterThanOrEqual(0.55 - 1e-9);
      expect(s.scale).toBeLessThanOrEqual(1 + 1e-9);
    }
  });

  it('collapses to the centre and fades out by the end', () => {
    const end = sphereFrame(SPHERE_MS, layout);
    for (const s of end) {
      expect(s.dx).toBeCloseTo(0, 9);
      expect(s.dy).toBeCloseTo(0, 9);
      expect(s.scale).toBeCloseTo(0, 9);
      expect(s.opacity).toBeCloseTo(0, 9);
    }
  });

  it('clamps past the end rather than overshooting into negative scale', () => {
    const past = sphereFrame(SPHERE_MS * 10, layout);
    for (const s of past) {
      expect(s.scale).toBeCloseTo(0, 9);
      expect(s.opacity).toBeGreaterThanOrEqual(0);
    }
  });

  it('fades on the EASED converge, not the raw one', () => {
    // points_showcase.dart:254 hands `easedConverge` to a parameter NAMED
    // `converge`. Porting the name instead of the argument makes the swarm
    // fade on a straight line. Half way through the converge window, an
    // easeInQuart is far behind linear — so opacity must still be HIGH.
    const midConverge = SPHERE_MS * (CONVERGE_START + (1 - CONVERGE_START) / 2);
    const mid = sphereFrame(midConverge, layout);
    const linearWouldBe = 0.5; // (1 - converge) at the midpoint
    const brightest = Math.max(...mid.map((s) => s.opacity));
    expect(brightest).toBeGreaterThan(linearWouldBe * 1.5);
  });

  it('spins the lattice about the y axis, leaving y untouched', () => {
    const a = sphereFrame(0, layout);
    const b = sphereFrame(SPHERE_MS * 0.25, layout);
    const dyOf = (frame: readonly { index: number; dy: number }[], index: number) =>
      frame.find((s) => s.index === index)!.dy;
    // y is the rotation axis: each seed's vertical offset is spin-invariant
    // while the converge has not started.
    for (let i = 0; i < STAR_COUNT; i++) {
      expect(dyOf(b, i)).toBeCloseTo(dyOf(a, i), 9);
    }
    // …and something actually moved horizontally.
    const movedX = Array.from({ length: STAR_COUNT }, (_, i) => {
      const from = a.find((s) => s.index === i)!.dx;
      const to = b.find((s) => s.index === i)!.dx;
      return Math.abs(to - from);
    });
    expect(Math.max(...movedX)).toBeGreaterThan(1);
  });

  it('completes SPIN_TURNS full turns across the timeline', () => {
    // After a whole number of turns the projection repeats. 1.4 turns is not
    // whole, so compare the fractional-turn point that IS: t at 1 full turn.
    const oneTurnMs = SPHERE_MS / SPIN_TURNS;
    const start = sphereFrame(0, layout);
    const oneTurn = sphereFrame(oneTurnMs, layout);
    // Same x offsets, because the converge has not begun by then either.
    expect(oneTurnMs).toBeLessThan(SPHERE_MS * CONVERGE_START);
    for (let i = 0; i < STAR_COUNT; i++) {
      const from = start.find((s) => s.index === i)!.dx;
      const to = oneTurn.find((s) => s.index === i)!.dx;
      expect(to).toBeCloseTo(from, 6);
    }
  });
});
