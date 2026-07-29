// Ports the `Curves.*` constants Flutter hands the celebration widgets for
// free — the ones this island's PER-FRAME drivers sample in JS.
//
// No single Dart file: `Curves` is `package:flutter/animation.dart`. The call
// sites are ../../../../../../CRM/lib/showcase/celebrations/sparkle_burst.dart
// (`easeOutQuart`), ../../../../../../CRM/lib/showcase/stats_showcase.dart
// (`easeOutQuart`, `easeInQuart`, `easeOutBack`, `easeOut`),
// ../../../../../../CRM/lib/shared/widgets/animation/count_up_text.dart
// (`easeOutExpo`) and
// ../../../../../../CRM/lib/showcase/rewards_card_showcase.dart
// (`easeInOutCubic`, the carousel's page tween).
//
// WHY HERE AND NOT IN `theme-react`. The library exports the CSS strings
// (`EASE_OUT`, `EASE_OUT_QUART`) and the one JS sampler a CSS entrance cannot
// cover. It deliberately carries no more: it is the app-agnostic RUNTIME, and a
// `Curves.easeOutBack` sampler is one app's celebration maths. Same line
// ../showcaseTokens.ts draws when it ports `HSLColor.withLightness` locally.
//
// WHY THE EXACT BEZIER SOLVE, not the familiar analytic twins. Every named ease
// in Flutter is a `Cubic` — `easeOutExpo` is `Cubic(0.19, 1, 0.22, 1)`, NOT
// `1 - 2^(-10t)`, and the two diverge visibly over a 1400ms count-up roll. The
// screens are reviewed running side by side with the Dart, so the port samples
// the same curve the framework does, using `Cubic.transformInternal`'s own
// bisection. A CSS-driven entrance needs none of this: `cubic-bezier()` IS the
// same curve, which is why `EASE_OUT_QUART` stays a string.

/** A Flutter `Curve`: maps a 0–1 clock onto a 0–1 (or overshooting) value. */
export type Curve = (t: number) => number;

/** Flutter's `clampDouble(t, 0, 1)` — every `Curve.transform` asserts this range. */
export function clamp01(value: number): number {
  return value < 0 ? 0 : value > 1 ? 1 : value;
}

/** `Cubic._cubicErrorBound`. */
const CUBIC_ERROR_BOUND = 0.001;

/**
 * A hard iteration cap Flutter does not have.
 *
 * `Cubic.transformInternal` bisects in a `while (true)`, which terminates for
 * every monotonic-in-x curve — all of the ones below. The cap is a browser-side
 * belt: a mistyped control point must not hang the frame loop. Bisection halves
 * the interval each pass, so 30 passes is ~1e-9 and is never reached in
 * practice; the result is byte-identical to Dart's.
 */
const MAX_ITERATIONS = 30;

/** `Cubic._evaluateCubic` — one axis of the unit cubic Bézier at parameter `m`. */
function evaluateCubic(a: number, b: number, m: number): number {
  return 3 * a * (1 - m) * (1 - m) * m + 3 * b * (1 - m) * m * m + m * m * m;
}

/**
 * Flutter's `Cubic(a, b, c, d)` — control points `(a, b)` and `(c, d)` on the
 * unit square — as a sampler. Solves x for the curve parameter by bisection,
 * then reads y off it, exactly as `transformInternal` does.
 */
export function cubic(a: number, b: number, c: number, d: number): Curve {
  return (t: number): number => {
    const x = clamp01(t);
    // `Curve.transform`'s own short-circuit, and it is load-bearing rather than
    // an optimisation: the bisection below stops within `_cubicErrorBound` of
    // the target x, so without this an ease would answer ~0.005 at t == 0 and
    // a phase that has not started yet would already be 0.5% of the way in.
    if (x === 0 || x === 1) return x;
    let start = 0;
    let end = 1;
    let midpoint = 0.5;
    for (let i = 0; i < MAX_ITERATIONS; i++) {
      midpoint = (start + end) / 2;
      const estimate = evaluateCubic(a, c, midpoint);
      if (Math.abs(x - estimate) < CUBIC_ERROR_BOUND) break;
      if (estimate < x) start = midpoint;
      else end = midpoint;
    }
    return evaluateCubic(b, d, midpoint);
  };
}

/**
 * The named eases these screens sample, at Flutter's own control points
 * (`package:flutter/src/animation/curves.dart`). Spelled as an object so a call
 * site reads `Curves.easeOutBack(t)` — one hop from the Dart it ports.
 */
export const Curves = Object.freeze({
  /** `Curves.easeOut`. */
  easeOut: cubic(0.25, 0.1, 0.25, 1),
  /** `Curves.easeOutQuart` — the app's motion law, and `EASE_OUT_QUART` in CSS. */
  easeOutQuart: cubic(0.165, 0.84, 0.44, 1),
  /** `Curves.easeInQuart`. */
  easeInQuart: cubic(0.895, 0.03, 0.685, 0.22),
  /** `Curves.easeOutExpo`. */
  easeOutExpo: cubic(0.19, 1, 0.22, 1),
  /** `Curves.easeOutBack` — the only one that overshoots 1. */
  easeOutBack: cubic(0.175, 0.885, 0.32, 1.275),
  /** `Curves.easeInOutCubic`. */
  easeInOutCubic: cubic(0.645, 0.045, 0.355, 1),
});

/**
 * `((t - from) / (to - from)).clamp(0, 1)` — the phase-local clock every one of
 * these sequences is written in terms of. `to === from` degrades to 1 rather
 * than dividing by zero (a zero-length phase is instantly over).
 */
export function phaseProgress(elapsedMs: number, fromMs: number, toMs: number): number {
  if (toMs <= fromMs) return elapsedMs < fromMs ? 0 : 1;
  return clamp01((elapsedMs - fromMs) / (toMs - fromMs));
}
