// The pure half of ./RewardsCarousel.tsx, which ports
// ../../../../../../CRM/lib/showcase/celebrations/rewards_carousel.dart.
//
// `RewardsCarousel`'s `AnimatedBuilder` recomputes one page's transform from
// the controller's FRACTIONAL page every frame:
//
//   offset  = page - controller.page          how far this page is from centre
//   clamped = offset.clamp(-1, 1)             beyond one slot nothing changes
//   t       = clamped.abs()
//   scale   = 1 - (1 - _minScale) * t
//   tiltY   = -clamped * _maxTilt             radians, about the y axis
//   matrix  = perspective(0.0015) * rotateY(tiltY) * scale
//
// All of that is arithmetic on one number, so it lives here and the component
// is left with the driver and the markup. It is also what a test can pin: the
// resting page must be face-on at full size, and a page one slot out must be at
// `_minScale` and fully tilted no matter how far past one slot it actually is.

/** `RewardsCarousel._featuredSize` — the circle's diameter, in px. */
export const FEATURED_SIZE = 208;

/** `RewardsCarousel._minScale` — how small a page one slot away shrinks to. */
export const MIN_SCALE = 0.56;

/** `RewardsCarousel._maxTilt` — the y-axis tilt of a one-slot-away page, in radians. */
export const MAX_TILT = 0.6;

/**
 * `Matrix4..setEntry(3, 2, 0.0015)`. Flutter's entry is 1/distance; CSS's
 * `perspective()` takes the distance itself, so it is the reciprocal.
 */
export const PERSPECTIVE_PX = 1 / 0.0015;

/**
 * `PageController(viewportFraction: 0.45)` — the share of the viewport one page
 * slot occupies. Set by the OWNER in Dart (`_resetPaging`), and carried here
 * because it is what turns a page offset into a distance on screen.
 */
export const VIEWPORT_FRACTION = 0.45;

/** `_slideDuration` in `rewards_card_showcase.dart` — one page advance. */
export const SLIDE_MS = 450;

/** One page's resolved cover-flow transform. */
export interface CoverFlowTransform {
  /** `1 - (1 - minScale) * t`. */
  readonly scale: number;
  /** `-clamped * maxTilt`, in radians. */
  readonly tiltRadians: number;
}

/** `offset.clamp(-1.0, 1.0)` then the two derivations above. */
export function coverFlowTransform(offset: number): CoverFlowTransform {
  const clamped = offset < -1 ? -1 : offset > 1 ? 1 : offset;
  const t = Math.abs(clamped);
  return { scale: 1 - (1 - MIN_SCALE) * t, tiltRadians: -clamped * MAX_TILT };
}

/**
 * `page % items.length`, on Dart's semantics.
 *
 * Dart's `%` on ints is always non-negative; JS's keeps the dividend's sign, so
 * a negative page (which a carousel seeded near zero can reach) would index
 * out of the list. The extra wrap is the same fix ../showcaseTokens.ts makes
 * for `hslHue`.
 */
export function wrapIndex(page: number, length: number): number {
  if (length <= 0) return 0;
  return ((page % length) + length) % length;
}
