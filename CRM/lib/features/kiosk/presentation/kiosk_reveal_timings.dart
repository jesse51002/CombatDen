import 'package:theme_flutter/theme/animation/celebration_timings.dart';

/// The beat sheet for the post-check-in glance's reveal.
///
/// **Two beats, not a cascade.** Founder ruling after watching the glance
/// assemble: everything arriving at once was cognitive overload, but so was a
/// long one-thing-at-a-time queue. So the screen now lands in exactly two
/// moves — the answer, then the payout.
///
/// **The order IS the information hierarchy.** The member's question in that
/// moment is "did it work, and into what?", so the answer leads and it leads
/// ALONE: the confirmation fades in CENTRED on the stage with nothing else on
/// screen to compete with it, and holds there. Only once it has been read does
/// it travel up to the top of the layout and hand the screen over to the
/// payout — the streak and the rewards, which arrive TOGETHER as one pair of
/// cards rather than one after the other.
///
/// The beats:
///
/// | at | what |
/// |----|------|
/// | 0ms | the confirmation fades in, CENTRED and alone ([confirmationFade]) |
/// | 1500ms | it lifts to its slot at the top ([centredHold] + [lift]) |
/// | 2220ms | BOTH panels, together — streak (counting up) and rewards |
///
/// The panels are the last beat, and `kKioskGlanceHold`'s ten seconds of
/// reading time start there — so the glance's whole life is ~12.2s. The
/// cascade inside the reward grid finishes 1.4s into that hold, leaving the
/// member well over eight seconds in front of a completely settled screen.
///
/// Nothing here applies under reduced motion: `KioskReveal` drops the wrapper
/// entirely, `KioskGlanceLift` renders the landed layout with no centred hold,
/// the check disc renders flat, and the streak shows its final number straight
/// away.
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

  /// How long the confirmation holds CENTRED on the stage, alone, before it
  /// moves. The founder's number, and the whole point of this choreography:
  /// the answer to "did it work?" gets the screen to itself long enough to be
  /// read, and not a beat longer — a member is standing in a doorway.
  static const Duration centredHold = Duration(milliseconds: 1500);

  /// The travel itself — the confirmation moving from the centre of the stage
  /// up into its slot at the top. Deliberately the slowest movement on the
  /// screen (1.5x a panel entrance): it is a beat of the choreography, not a
  /// cut, and a member's eye has to be able to follow it up.
  static const Duration lift = Duration(milliseconds: 720);

  /// Beat 2 — the streak and rewards panels, TOGETHER, once the confirmation
  /// has LANDED ([centredHold] + [lift]). They never start mid-travel: the
  /// member watches the confirmation move, and only then does the payout
  /// arrive. One [KioskReveal] wraps the whole row, so "together" is
  /// structural rather than two offsets that happen to match.
  ///
  /// The LAST beat: `kKioskGlanceHold` starts here.
  static const Duration panels = Duration(milliseconds: 2220);

  /// The gap between consecutive reward tiles inside the grid, so they arrive
  /// visibly one by one rather than as a ripple — slow enough to read as four
  /// deliberate arrivals. The two PANELS land together; the tiles inside the
  /// rewards panel are the one place a stagger survives, because there the
  /// cascade is the payout reading as a payout.
  static const Duration tileStagger = Duration(milliseconds: 320);

  /// The streak numeral's count-up roll — the payoff beat, and the longest
  /// single thing on the screen. It runs at the member app's own celebration
  /// length ([CelebrationTimings.countUpDuration]) because that is what makes
  /// a two-digit week count read as a *roll* rather than a number swap. It
  /// starts on [panels], so the number is already moving as its card lands.
  static const Duration countUp = CelebrationTimings.countUpDuration;

  /// One panel's or tile's fade + rise, and the cross-fade between kiosk
  /// views. Everything except the confirmation, the lift and the count-up.
  static const Duration element = Duration(milliseconds: 480);
}
