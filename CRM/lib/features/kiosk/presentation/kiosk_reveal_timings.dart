import 'package:theme_flutter/theme/animation/celebration_timings.dart';

/// The beat sheet for the post-check-in glance's reveal.
///
/// **The order IS the information hierarchy.** The member's question in that
/// moment is "did it work, and into what?", so the answer lands first — the
/// check disc popping in beside the named class. Only then does the reward get
/// paid out: the streak, its numeral rolling up, then the reward tiles
/// cascading in one by one. A glance that showed the points before the
/// confirmation would be answering a question nobody asked.
///
/// **Every beat has to be individually perceptible** (founder ruling, watching
/// it run on the kiosk). These durations are deliberately 2-3x the app's
/// standard entrance: at [CelebrationTimings.revealDuration] speed the whole
/// choreography reads as a flicker, and the count-up in particular — the
/// payoff moment — has to feel deliberate and satisfying rather than glitchy.
/// The reveal lands around 2s and the 8-second dwell only starts after it
/// (`kKioskGlanceRevealSettle`), so the member reads a finished screen for the
/// full eight seconds; the glance's total life growing to ~10s is the intended
/// trade, not a regression.
///
/// Nothing here applies under reduced motion: `KioskReveal` drops the wrapper
/// entirely, the check disc renders flat, and the streak shows its final
/// number straight away.
class KioskRevealTimings {
  const KioskRevealTimings._();

  /// Beat 1 — the confirmation (check disc + the named class). It leads, with
  /// no delay at all, but it is NOT simply present: it fades in over
  /// [confirmationFade], the slowest single entrance on the screen. It was the
  /// one element with no entrance of its own, which is what made the arrival
  /// read as a hard cut even once everything below it animated.
  static const Duration confirmation = Duration.zero;

  /// The confirmation's own fade + rise, longer than the panels' so the first
  /// beat is unmistakably an entrance.
  static const Duration confirmationFade = Duration(milliseconds: 560);

  /// Beat 2 — the streak panel, once the confirmation has landed.
  static const Duration streak = Duration(milliseconds: 620);

  /// Beat 3 — the points + rewards panel.
  static const Duration rewards = Duration(milliseconds: 980);

  /// The gap between consecutive reward tiles inside the grid, so they arrive
  /// visibly one by one rather than as a ripple. Measured from the GRID's own
  /// mount (the catalog + balance are still in flight when the glance opens),
  /// not from the glance's first frame — the panel's own [rewards] reveal is
  /// what keeps them behind the streak regardless of when the fetch lands.
  static const Duration tileStagger = Duration(milliseconds: 180);

  /// The streak numeral's count-up roll — the payoff beat, and the longest
  /// single thing on the screen. It runs at the member app's own celebration
  /// length ([CelebrationTimings.countUpDuration]) because that is what makes
  /// a two-digit week count read as a *roll* rather than a number swap.
  static const Duration countUp = CelebrationTimings.countUpDuration;

  /// One panel's or tile's fade + rise, and the cross-fade between kiosk
  /// views. Everything except the confirmation and the count-up.
  static const Duration element = Duration(milliseconds: 480);
}
