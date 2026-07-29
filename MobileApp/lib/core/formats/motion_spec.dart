import 'package:flutter/animation.dart';

import 'package:mobile_app/core/formats/motion_formats.dart';

/// The resolved timing set for a [MotionPersonality].
///
/// [MotionPersonality.standard] reproduces
/// `shared/widgets/animation/celebration_timings.dart` value for value,
/// so an unbranded build and any tenant without the slot animate
/// exactly as the app does today.
class MotionSpec {
  const MotionSpec({
    required this.revealDuration,
    required this.revealStagger,
    required this.badgeStagger,
    required this.countUpDuration,
    required this.sparkleWindow,
    required this.sparkleFade,
    required this.pulseDuration,
    required this.curve,
    required this.particleCount,
  });

  /// Standard fade + slide entrance for a single element.
  final Duration revealDuration;

  /// Delay between consecutive reveals in a stack.
  final Duration revealStagger;

  /// Delay between consecutive badges/tiles in a cascade row.
  final Duration badgeStagger;

  /// Duration of a count-up roll. Exceeds the element ceiling on
  /// purpose across every personality: a count-up is a *value* tween,
  /// not a state transition, and the long slow landing is the payoff.
  final Duration countUpDuration;

  /// Total window over which a sparkle scatter fades in.
  final Duration sparkleWindow;

  /// Per-particle fade-in slice inside the sparkle window.
  final Duration sparkleFade;

  /// One-shot pulse for badges, icons, and accent text.
  final Duration pulseDuration;

  /// The entrance curve. Ease-out in every personality — the app's
  /// motion law bans bounce and elastic, and a personality is not
  /// allowed to smuggle that change in as a token.
  final Curve curve;

  /// Decorative particle count for sparkle surfaces. Zero means the
  /// personality wants no decoration at all.
  final int particleCount;

  /// The app-wide per-element ceiling, from `MobileApp/CLAUDE.md` and
  /// `PRODUCT.md`: ease-out, no bounce, at most 300ms.
  ///
  /// [MotionPersonality.cinematic] is authored at 420ms and is clamped
  /// to this ceiling, finding its weight in stagger and count-up length
  /// instead. That keeps ONE motion law for the whole app. If the
  /// ceiling is instead ruled to be per-personality, raise it here and
  /// in both docs — it is deliberately a single constant so the ruling
  /// is a one-line change.
  static const Duration elementDurationCeiling = Duration(milliseconds: 300);

  /// The authored (pre-clamp) element duration per personality, kept so
  /// the intent survives the clamp and the ruling stays legible.
  static const Map<MotionPersonality, Duration> authoredElementDuration = {
    MotionPersonality.standard: Duration(milliseconds: 260),
    MotionPersonality.calm: Duration(milliseconds: 220),
    MotionPersonality.hype: Duration(milliseconds: 200),
    MotionPersonality.cinematic: Duration(milliseconds: 420),
  };

  static Duration _clamped(MotionPersonality personality) {
    final authored = authoredElementDuration[personality]!;
    return authored > elementDurationCeiling
        ? elementDurationCeiling
        : authored;
  }

  /// Resolve the timing set for [personality].
  factory MotionSpec.forPersonality(MotionPersonality personality) {
    final reveal = _clamped(personality);
    return switch (personality) {
      MotionPersonality.standard => MotionSpec(
        revealDuration: reveal,
        revealStagger: const Duration(milliseconds: 90),
        badgeStagger: const Duration(milliseconds: 70),
        countUpDuration: const Duration(milliseconds: 1400),
        sparkleWindow: const Duration(milliseconds: 620),
        sparkleFade: const Duration(milliseconds: 220),
        pulseDuration: const Duration(milliseconds: 240),
        curve: Curves.easeOutQuart,
        particleCount: 12,
      ),
      MotionPersonality.calm => MotionSpec(
        revealDuration: reveal,
        revealStagger: const Duration(milliseconds: 40),
        badgeStagger: const Duration(milliseconds: 32),
        countUpDuration: const Duration(milliseconds: 900),
        sparkleWindow: const Duration(milliseconds: 520),
        sparkleFade: const Duration(milliseconds: 200),
        pulseDuration: const Duration(milliseconds: 220),
        curve: Curves.easeOutSine,
        particleCount: 0,
      ),
      MotionPersonality.hype => MotionSpec(
        revealDuration: reveal,
        revealStagger: const Duration(milliseconds: 55),
        badgeStagger: const Duration(milliseconds: 42),
        countUpDuration: const Duration(milliseconds: 1100),
        sparkleWindow: const Duration(milliseconds: 520),
        sparkleFade: const Duration(milliseconds: 180),
        pulseDuration: const Duration(milliseconds: 200),
        curve: Curves.easeOutExpo,
        particleCount: 20,
      ),
      MotionPersonality.cinematic => MotionSpec(
        revealDuration: reveal,
        revealStagger: const Duration(milliseconds: 140),
        badgeStagger: const Duration(milliseconds: 110),
        countUpDuration: const Duration(milliseconds: 2000),
        sparkleWindow: const Duration(milliseconds: 900),
        sparkleFade: const Duration(milliseconds: 300),
        pulseDuration: const Duration(milliseconds: 300),
        curve: Curves.easeOutQuint,
        particleCount: 8,
      ),
    };
  }
}
