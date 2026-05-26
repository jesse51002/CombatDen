import 'package:flutter/widgets.dart';

import 'package:customization_engine/showcase/booking_showcase.dart';
import 'package:customization_engine/showcase/home_showcase.dart';
import 'package:customization_engine/showcase/points_showcase.dart';
import 'package:customization_engine/showcase/rewards_card_showcase.dart';
import 'package:customization_engine/showcase/rewards_showcase.dart';
import 'package:customization_engine/showcase/stats_showcase.dart';
import 'package:customization_engine/showcase/wins_showcase.dart';

/// The member-app surfaces previewable in the live theme preview, in
/// slideshow order. Each maps to a self-contained showcase widget that
/// themes itself live from the loaded customization (so switching theme
/// re-paints it) and — for the celebrations — loops its motion.
///
/// Gym identity ([gymName] / [gymLogo]) is NOT a customization slot: it is
/// owned by the host app (AppManagement) and passed in here as arguments.
/// Only the surfaces that show the gym header (home, store) consume them.
///
/// A consumer cycles [values] and renders [build] inside a phone frame; it
/// does NOT need to know the individual widget classes.
enum ShowcaseScreen {
  home('Home'),
  booking('Booking'),
  streak('Streak'),
  points('Points'),
  rewards('Rewards'),
  wins('Achievements'),
  store('Store');

  const ShowcaseScreen(this.label);

  /// Short human label for the view selector / captions.
  final String label;

  /// Builds the showcase widget for this surface. [loop] keeps the animated
  /// surfaces running; [onCycleComplete] fires once per loop. [gymName] /
  /// [gymLogo] are the host app's gym identity, used only by the surfaces
  /// that render the gym header.
  Widget build({
    bool loop = true,
    VoidCallback? onCycleComplete,
    String gymName = 'Your Gym',
    ImageProvider? gymLogo,
  }) {
    switch (this) {
      case ShowcaseScreen.home:
        return HomeShowcase(
          loop: loop,
          onCycleComplete: onCycleComplete,
          gymName: gymName,
          gymLogo: gymLogo,
        );
      case ShowcaseScreen.booking:
        return BookingShowcase(loop: loop, onCycleComplete: onCycleComplete);
      case ShowcaseScreen.streak:
        return StatsShowcase(loop: loop, onCycleComplete: onCycleComplete);
      case ShowcaseScreen.points:
        return PointsShowcase(loop: loop, onCycleComplete: onCycleComplete);
      case ShowcaseScreen.rewards:
        return RewardsCardShowcase(
          loop: loop,
          onCycleComplete: onCycleComplete,
        );
      case ShowcaseScreen.wins:
        return WinsShowcase(loop: loop, onCycleComplete: onCycleComplete);
      case ShowcaseScreen.store:
        return RewardsShowcase(
          loop: loop,
          onCycleComplete: onCycleComplete,
          gymName: gymName,
          gymLogo: gymLogo,
        );
    }
  }
}
