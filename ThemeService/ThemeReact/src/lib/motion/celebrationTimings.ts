// Ports ../../ThemeFlutter/lib/theme/animation/celebration_timings.dart.
//
// Durations are plain MILLISECONDS rather than a `Duration` type: a CSS
// `transition-duration` and a `setTimeout` both want a number, so wrapping it
// would only add unwrapping.

/**
 * Durations and stagger delays for the post-class celebration scaffold.
 *
 * Kept out of the design tokens because these are celebration-specific timings,
 * not fungible app-wide values. Per-element transitions stay inside the ≤300ms
 * ease-out budget; the sense of celebration comes from stacking many short
 * beats with staggered starts, not from any single long animation.
 */
export const CelebrationTimings = Object.freeze({
  /** Standard fade + 12px slide entrance for a single element. */
  revealMs: 260,

  /** Delay between consecutive staggered reveals in a stack. */
  revealStaggerMs: 90,

  /** Delay between consecutive badges/tiles in a cascade row. */
  badgeStaggerMs: 70,

  /**
   * Duration of a count-up roll. Exceeds the per-element 300ms ceiling on
   * purpose: count-ups are VALUE tweens, not state transitions, and the
   * pronounced deceleration (fast front-loaded scroll, long slow landing) is
   * the celebration payoff.
   */
  countUpMs: 1400,

  /** Total window over which a sparkle scatter fades in. */
  sparkleWindowMs: 620,

  /** Per-particle fade-in slice inside the sparkle window. */
  sparkleFadeMs: 220,

  /** One-shot pulse for badges, icons, and accent text. */
  pulseMs: 240,
});
