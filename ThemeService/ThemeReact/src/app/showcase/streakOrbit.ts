// The pure half of ./StatsShowcase.tsx, which ports
// ../../../../../CRM/lib/showcase/stats_showcase.dart.
//
// `_StreakOrbitState` runs ONE `AnimationController` over the whole intro and
// slices its 0–1 value into five phases inside a single `AnimatedBuilder`. That
// makes every particle's position a function of one clock — which is exactly
// why the port drives it with `requestAnimationFrame` instead of CSS: eight
// icons on a shared, non-monotonic radius (grow, then collapse) around a
// rotating ring is not a set of independent property tweens.
//
// So the arithmetic lives here, as plain functions of elapsed milliseconds and
// the measured box, and ./StatsShowcase.tsx is left with the driver and the
// markup. It is also what a test can pin: a phase boundary that drifts is
// invisible in a screenshot and obvious in an assertion.
//
// The Dart computes its boundaries as FRACTIONS of the controller
// (`delayEnd = d / total`) and then rebuilds phase-local clocks out of them.
// Both steps divide by the same total, so the port works in milliseconds
// directly and lands on identical values with one fewer round trip.

import { Curves, clamp01, phaseProgress } from './celebrations/curves';

/** `_kDelay` — a beat of empty space before anything appears. */
export const DELAY_MS = 500;
/** `_kRingGrow` — the mini-icon ring expanding outward. */
export const RING_GROW_MS = 600;
/** `_kRingCollapse` — and immediately collapsing back to the centre. */
export const RING_COLLAPSE_MS = 500;
/** `_kIconPop` — the big streak icon's overshooting entrance. */
export const ICON_POP_MS = 400;
/** `_kIconHold` — it sits there. */
export const ICON_HOLD_MS = 800;
/** `_kIconExit` — then fades out into the stats cascade. */
export const ICON_EXIT_MS = 250;

/** `_kOrbitCount`. */
export const ORBIT_COUNT = 8;
/** `_kSpinTurns` — full turns the ring makes across the WHOLE timeline. */
export const SPIN_TURNS = 1.6;
/** `_kOrbitSize` — a mini icon's edge at the reference extent. */
export const ORBIT_SIZE = 30;
/** `_kIconSize` — the big icon's edge at the reference extent. */
export const ICON_SIZE = 120;
/** `_kReferenceExtent` — the box the two sizes above are quoted against. */
export const REFERENCE_EXTENT = 280;
/** `_kEdgePad` — how far short of the box's edge the ring stops. */
export const EDGE_PAD = 28;

/** `_kStatsHold` — how long the stats statement holds before the orbit replays. */
export const STATS_HOLD_MS = 2600;

/** `AnimationController.duration` — the intro's whole timeline. */
export const ORBIT_TOTAL_MS =
  DELAY_MS + RING_GROW_MS + RING_COLLAPSE_MS + ICON_POP_MS + ICON_HOLD_MS + ICON_EXIT_MS;

/** The phase boundaries, in ms from the start. `delayEnd`, `ringGrowEnd`, … */
export const DELAY_END_MS = DELAY_MS;
export const RING_GROW_END_MS = DELAY_END_MS + RING_GROW_MS;
export const RING_END_MS = RING_GROW_END_MS + RING_COLLAPSE_MS;
export const ICON_POP_END_MS = RING_END_MS + ICON_POP_MS;
export const ICON_HOLD_END_MS = ICON_POP_END_MS + ICON_HOLD_MS;

/** What `LayoutBuilder` resolves once per size — the `renderScale` block. */
export interface OrbitLayout {
  /** `smallerExtent / _kReferenceExtent`. */
  readonly renderScale: number;
  /** `_kOrbitSize * renderScale`. */
  readonly orbitSize: number;
  /** `_kIconSize * renderScale`. */
  readonly iconSize: number;
  /** `smallerExtent / 2 - _kEdgePad - orbitSize / 2`. */
  readonly maxRadius: number;
}

/** `LayoutBuilder(builder: (context, constraints) { … })`, verbatim. */
export function orbitLayout(width: number, height: number): OrbitLayout {
  const smallerExtent = Math.min(width, height);
  const renderScale = smallerExtent / REFERENCE_EXTENT;
  const orbitSize = ORBIT_SIZE * renderScale;
  return {
    renderScale,
    orbitSize,
    iconSize: ICON_SIZE * renderScale,
    maxRadius: smallerExtent / 2 - EDGE_PAD - orbitSize / 2,
  };
}

/** Everything the `AnimatedBuilder` resolves for one frame. */
export interface OrbitFrame {
  /** `radiusFactor` — 0 → 1 (grow), 1 → 0 (collapse). Also the ring's opacity. */
  readonly radiusFactor: number;
  /** `maxRadius * radiusFactor`. */
  readonly radius: number;
  /** `t * 2 * pi * _kSpinTurns`, in radians. */
  readonly spin: number;
  /** `easeOutBack(iconPopT) * (1 - 0.3 * iconExitE)`. Overshoots 1 on the pop. */
  readonly iconScale: number;
  /** `easeOut(iconPopT) * (1 - iconExitE)`. */
  readonly iconOpacity: number;
}

/** The `AnimatedBuilder`'s body, as a function of elapsed ms and the box. */
export function orbitFrame(elapsedMs: number, maxRadius: number): OrbitFrame {
  const e = elapsedMs < 0 ? 0 : elapsedMs > ORBIT_TOTAL_MS ? ORBIT_TOTAL_MS : elapsedMs;

  // Mini-icon ring: expand → collapse to centre (no hold).
  const expandE = Curves.easeOutQuart(phaseProgress(e, DELAY_END_MS, RING_GROW_END_MS));
  const ringCollapseE = Curves.easeInQuart(phaseProgress(e, RING_GROW_END_MS, RING_END_MS));
  const radiusFactor = expandE * (1 - ringCollapseE);

  // Big centre icon: pops only AFTER the ring has collapsed, holds, fades out.
  const iconPopT = phaseProgress(e, RING_END_MS, ICON_POP_END_MS);
  const iconExitE = Curves.easeInQuart(phaseProgress(e, ICON_HOLD_END_MS, ORBIT_TOTAL_MS));

  return {
    radiusFactor,
    radius: maxRadius * radiusFactor,
    spin: (e / ORBIT_TOTAL_MS) * 2 * Math.PI * SPIN_TURNS,
    iconScale: Curves.easeOutBack(iconPopT) * (1 - 0.3 * iconExitE),
    iconOpacity: clamp01(Curves.easeOut(iconPopT) * (1 - iconExitE)),
  };
}

/** `_orbitIcon`'s offset: `Offset(cos(theta) * radius, sin(theta) * radius)`. */
export function orbitOffset(index: number, spin: number, radius: number): { x: number; y: number } {
  const theta = spin + (index * 2 * Math.PI) / ORBIT_COUNT;
  return { x: Math.cos(theta) * radius, y: Math.sin(theta) * radius };
}
