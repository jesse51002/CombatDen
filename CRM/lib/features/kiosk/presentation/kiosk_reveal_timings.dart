import 'package:theme_flutter/theme/animation/celebration_timings.dart';

/// The beat sheet for the post-check-in glance's reveal: TWO beats, not a
/// cascade (founder ruling — all-at-once was cognitive overload, and so was a
/// long one-at-a-time queue). The order is the information hierarchy: the
/// confirmation fades in CENTRED and alone, holds, then lifts to the top; only
/// once it has landed do the streak and rewards panels arrive TOGETHER.
///
/// None of it applies under reduced motion — `KioskReveal`, `KioskGlanceLift`,
/// the check disc and the streak each render their landed state directly.
class KioskRevealTimings {
  const KioskRevealTimings._();

  /// Beat 1 — the confirmation (check disc + the named class). Leads, no delay.
  static const Duration confirmation = Duration.zero;

  /// The confirmation's fade + rise, longer than a panel's so the first beat
  /// is unmistakably an entrance.
  static const Duration confirmationFade = Duration(milliseconds: 560);

  /// How long the confirmation holds centred and alone before it moves — long
  /// enough to be read and not a beat longer (the founder's number; a member
  /// is standing in a doorway).
  static const Duration centredHold = Duration(milliseconds: 1500);

  /// The travel from centre stage up into the top slot. Deliberately the
  /// slowest movement on the screen: a beat of the choreography, not a cut.
  static const Duration lift = Duration(milliseconds: 720);

  /// Beat 2 — the streak and rewards panels, TOGETHER, and only once the
  /// confirmation has LANDED ([centredHold] + [lift]); they never start
  /// mid-travel. One [KioskReveal] wraps the row, so "together" is structural
  /// rather than two offsets that happen to match. The LAST beat, so
  /// `kKioskGlanceHold`'s reading time starts here.
  static const Duration panels = Duration(milliseconds: 2220);

  /// The gap between reward tiles inside the grid — the one place a stagger
  /// survives, because there the cascade is the payout reading as a payout.
  static const Duration tileStagger = Duration(milliseconds: 320);

  /// The streak numeral's count-up roll, starting on [panels] so the number is
  /// already moving as its card lands. Runs at the member app's own
  /// celebration length so a week count reads as a *roll*, not a number swap.
  static const Duration countUp = CelebrationTimings.countUpDuration;

  /// One panel's or tile's fade + rise, and the cross-fade between kiosk views
  /// — everything except the confirmation, the lift and the count-up.
  static const Duration element = Duration(milliseconds: 480);
}
