// The pure half of ./PointsShowcase.tsx, which ports
// ../../../../../CRM/lib/showcase/points_showcase.dart.
//
// `_PointSphereState` seeds fourteen stars on a UNIT SPHERE once
// (`_buildSphere`, a `static final` — computed on first use and shared by every
// instance), then re-projects all fourteen to 2D inside a single
// `AnimatedBuilder` on every frame: one Y-axis spin angle, one converge factor,
// one depth sort. Every star's position, scale and opacity is a function of
// that ONE clock, which is exactly why ./PointsShowcase.tsx drives it with
// `requestAnimationFrame` rather than CSS — fourteen particles sharing a
// rotating projection is not a set of independent property tweens.
//
// So the arithmetic lives here, as plain functions of elapsed milliseconds and
// the measured box, and the component is left with the driver and the markup.
// It is also what a test can pin: a Fibonacci lattice that drifts, a converge
// that starts a beat early, or a depth sort that runs backwards are all
// invisible in a screenshot and obvious in an assertion.
//
// The Dart works in the controller's own 0–1 value and rebuilds phase-local
// clocks out of it; the port works in milliseconds and divides once, landing on
// identical values with one fewer round trip. Same trade ./streakOrbit.ts makes.

import { Curves, clamp01 } from './celebrations/curves';

/** `_kSphereDuration` — the swarm's whole timeline. */
export const SPHERE_MS = 1700;

/** `_kSpinTurns` — full Y-axis turns across that timeline. */
export const SPIN_TURNS = 1.4;

/** `_kConvergeStart` — the fraction of the timeline at which the collapse begins. */
export const CONVERGE_START = 0.74;

/** `_kStarCount`. */
export const STAR_COUNT = 14;

/**
 * `_kGoldenAngle`. The Dart's own literal, NOT `pi * (3 - sqrt(5))`
 * (2.39996322…): the two differ in the sixth decimal, and after thirteen
 * multiplications that is a visible rotation of the lattice.
 */
export const GOLDEN_ANGLE = 2.39996;

/** `_kReferenceExtent` — the box the seed sizes below are quoted against. */
export const REFERENCE_EXTENT = 280;

/** `edgePad`'s unscaled value — how far short of the box's edge the swarm stops. */
export const EDGE_PAD = 28;

/** `_kHeroSize` — the focused stat illustration's edge, in px. */
export const HERO_SIZE = 238;

/** `_kPointsHold` — how long the focused content holds before the sphere replays. */
export const POINTS_HOLD_MS = 2600;

/** `_buildSphere`'s `sizes` table, cycled by `i % sizes.length`. */
export const STAR_SIZES: readonly number[] = Object.freeze([28, 36, 32, 40, 30]);

/** `_StarSeed` — one star's resting point on the unit sphere, plus its art size. */
export interface StarSeed {
  readonly x: number;
  readonly y: number;
  readonly z: number;
  /** Edge of the star's art at the reference extent, in px. */
  readonly size: number;
}

/**
 * `_buildSphere` — a Fibonacci (golden-angle) lattice: `y` steps evenly down
 * the axis, `r` is the ring radius at that latitude, and `theta` advances by the
 * golden angle so successive points never line up into visible spirals.
 */
function buildSphere(): readonly StarSeed[] {
  const seeds: StarSeed[] = [];
  for (let i = 0; i < STAR_COUNT; i++) {
    const y = 1 - (2 * (i + 0.5)) / STAR_COUNT;
    const r = Math.sqrt(1 - y * y);
    const theta = i * GOLDEN_ANGLE;
    seeds.push(
      Object.freeze({
        x: r * Math.cos(theta),
        y,
        z: r * Math.sin(theta),
        size: STAR_SIZES[i % STAR_SIZES.length] ?? 0,
      }),
    );
  }
  return Object.freeze(seeds);
}

/** `_PointSphereState._seeds` — built once, shared by every mount. */
export const STAR_SEEDS: readonly StarSeed[] = buildSphere();

/** What `LayoutBuilder` resolves once per size — the `renderScale` block. */
export interface SphereLayout {
  /** `smallerExtent / _kReferenceExtent`. */
  readonly renderScale: number;
  /** `28 * renderScale`. */
  readonly edgePad: number;
  /** `constraints.maxWidth / 2`. */
  readonly halfWidth: number;
  /** `constraints.maxHeight / 2`. */
  readonly halfHeight: number;
}

/**
 * `LayoutBuilder(builder: (context, constraints) { … })`, verbatim.
 *
 * The art scales off the SMALLER extent so the stars do not become gigantic on
 * a tall screen, while the orbital path uses each axis independently — which is
 * what stretches the sphere into an ellipsoid that fills width AND height.
 */
export function sphereLayout(width: number, height: number): SphereLayout {
  const smallerExtent = Math.min(width, height);
  const renderScale = smallerExtent / REFERENCE_EXTENT;
  return {
    renderScale,
    edgePad: EDGE_PAD * renderScale,
    halfWidth: width / 2,
    halfHeight: height / 2,
  };
}

/** `Image(width: p.seed.size * renderScale)` — one star's art box, in px. */
export function starSize(index: number, renderScale: number): number {
  return (STAR_SEEDS[index]?.size ?? 0) * renderScale;
}

/** One star's resolved frame — `_renderStar`'s arguments, already evaluated. */
export interface ProjectedStar {
  /** Which seed this is, so the driver can find its element. */
  readonly index: number;
  /** `Offset(p.x * radiusX, …)`. */
  readonly dx: number;
  /** `Offset(…, -p.seed.y * radiusY)` — Flutter's y axis points DOWN. */
  readonly dy: number;
  /** `(1 - converge) * (0.55 + 0.45 * depth)`. */
  readonly scale: number;
  /** `(1 - converge) * (0.4 + 0.6 * depth)`. */
  readonly opacity: number;
  /** Paint order, back (0) to front. Dart's `..sort((a, b) => a.z.compareTo(b.z))`. */
  readonly order: number;
}

/**
 * The `AnimatedBuilder`'s body, as a function of elapsed ms and the box.
 *
 * Returned in PAINT order (back to front) so the caller can hand `order`
 * straight to `z-index`, which is what Dart gets for free from the sorted
 * `Stack`'s child order.
 *
 * NOTE `_renderStar`'s third parameter is named `converge` but is handed
 * `easedConverge` at the call site (points_showcase.dart:254) — so the scale
 * and opacity ramps read the EASED value, not the raw one. Porting the
 * parameter name instead of the argument would make the swarm fade out on a
 * straight line rather than the ease-in-quart the screen actually shows.
 */
export function sphereFrame(elapsedMs: number, layout: SphereLayout): readonly ProjectedStar[] {
  const t = clamp01(elapsedMs / SPHERE_MS);
  const spin = t * 2 * Math.PI * SPIN_TURNS;
  const converge = clamp01((t - CONVERGE_START) / (1 - CONVERGE_START));
  const easedConverge = Curves.easeInQuart(converge);
  const radiusX = (layout.halfWidth - layout.edgePad) * (1 - easedConverge);
  const radiusY = (layout.halfHeight - layout.edgePad) * (1 - easedConverge);

  const cosA = Math.cos(spin);
  const sinA = Math.sin(spin);
  // The Y-axis rotation: x and z turn, y is the axis and is left alone.
  const projected = STAR_SEEDS.map((seed, index) => ({
    seed,
    index,
    x: seed.x * cosA + seed.z * sinA,
    z: -seed.x * sinA + seed.z * cosA,
  }));
  projected.sort((a, b) => a.z - b.z);

  return projected.map((p, order) => {
    // 0 (back) → 1 (front). Drives both the size and the fade, which is what
    // makes a flat projection read as depth.
    const depth = (p.z + 1) / 2;
    return Object.freeze({
      index: p.index,
      dx: p.x * radiusX,
      dy: -p.seed.y * radiusY,
      scale: (1 - easedConverge) * (0.55 + 0.45 * depth),
      opacity: (1 - easedConverge) * (0.4 + 0.6 * depth),
      order,
    });
  });
}
