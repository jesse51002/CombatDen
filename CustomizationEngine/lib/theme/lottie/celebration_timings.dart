/// Durations and stagger delays used by the post-class celebration scaffold.
///
/// Lives outside `DesignConstants` (which is immutable) because these are
/// celebration-specific timings, not fungible app-wide design tokens. Per-
/// element transitions stay inside the app's ≤300ms ease-out budget; the
/// overall sense of celebration comes from stacking many short beats with
/// staggered start times, not from any single long animation.
class CelebrationTimings {
  const CelebrationTimings._();

  /// Standard fade + 12px slide entrance for a single element.
  static const Duration revealDuration = Duration(milliseconds: 260);

  /// Delay between consecutive [StaggeredReveal]s in a stack.
  static const Duration revealStagger = Duration(milliseconds: 90);

  /// Delay between consecutive badges/tiles in a cascade row.
  static const Duration badgeStagger = Duration(milliseconds: 70);

  /// Duration of a count-up roll. Exceeds the per-element 300ms ceiling on
  /// purpose: count-ups are *value* tweens, not state transitions, and the
  /// pronounced exponential deceleration (front-loaded fast scroll, long
  /// slow landing) is the celebration payoff.
  static const Duration countUpDuration = Duration(milliseconds: 1400);

  /// Total window over which a sparkle scatter fades in.
  static const Duration sparkleWindow = Duration(milliseconds: 620);

  /// Per-particle fade-in slice inside the sparkle window.
  static const Duration sparkleFade = Duration(milliseconds: 220);

  /// One-shot pulse for badges, icons, and accent text.
  static const Duration pulseDuration = Duration(milliseconds: 240);
}
