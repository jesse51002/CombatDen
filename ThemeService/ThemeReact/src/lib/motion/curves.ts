// Ports the motion law of ../../ThemeFlutter/lib/theme/animation/scale_reveal.dart.
//
// The Dart file is a `StatefulWidget` driving an `AnimationController`; on the
// web a CSS transition does the same job with no JS timeline, so what ports is
// the CURVE and the entrance's shape, not the widget. `ScaleReveal` there is
// literally "ease-out-quart, fade 0→1, scale `startScale`→1", which is a
// two-property CSS transition.

/**
 * Flutter's `Curves.easeOutQuart` — `Cubic(0.165, 0.84, 0.44, 1.0)` — as CSS.
 * The app's motion law: ease-out, no bounce, ≤300ms.
 */
export const EASE_OUT_QUART = 'cubic-bezier(0.165, 0.84, 0.44, 1)';

/** Flutter's `Curves.easeOut`, for transitions that do not want the quart snap. */
export const EASE_OUT = 'cubic-bezier(0.25, 0.1, 0.25, 1)';

/**
 * The same curve sampled in JS, for anything tweening a value by hand (a
 * count-up, a canvas draw) rather than through CSS. `t` is clamped to 0–1.
 */
export function easeOutQuart(t: number): number {
  const clamped = t < 0 ? 0 : t > 1 ? 1 : t;
  return 1 - Math.pow(1 - clamped, 4);
}

/** The starting scale of a `ScaleReveal` entrance. Smaller feels poppier. */
export const SCALE_REVEAL_START_SCALE = 0.5;
