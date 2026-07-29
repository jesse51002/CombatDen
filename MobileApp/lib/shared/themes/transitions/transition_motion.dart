import 'package:flutter/animation.dart';

/// The shared motion law for every authored page transition.
///
/// A page transition answers a tap, so it carries two rules the
/// celebration surfaces do not:
///
/// * **No lead-in.** Every authored value starts moving on frame one.
///   A delay before a screen responds reads as input lag, never as
///   drama, so no curve here may be wrapped in an `Interval` that
///   starts above zero.
/// * **A legibility floor.** The job of a transition is to say where
///   you went and where you came from, and a movement too short to
///   perceive says nothing — it reads as a flicker, not as travel.
///   Values are free to differ in length (`cardStack` travels further
///   than `fade`, so it takes longer), but none of them may fall under
///   [legibilityFloor].
///
/// `TransitionStyle.platformDefault` and `TransitionStyle.none` sit
/// outside the floor on purpose: the first is whatever the platform
/// already does, and the second is a deliberate zero-length cut.
class TransitionMotion {
  // Private constructor to prevent instantiation
  TransitionMotion._();

  /// The shortest a full-screen movement may run and still be read as a
  /// movement. 200ms is Material's `short4` token — the shortest
  /// duration Material assigns to a full-container transition — and
  /// below it the eye registers a jump rather than travel, which loses
  /// the "where did I come from" cue that is the transition's whole
  /// purpose.
  static const Duration legibilityFloor = Duration(milliseconds: 200);

  /// Translation curve. Ease-out, like the rest of the app: no bounce,
  /// no elastic, no anticipation.
  static const Curve travel = Curves.easeOutCubic;

  /// Opacity curve. Ease-out for the same reason.
  static const Curve fade = Curves.easeOut;
}
