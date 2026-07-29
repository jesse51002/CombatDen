import 'package:flutter/material.dart';
import 'package:mobile_app/shared/widgets/sparkle_hero/sparkle_hero.dart';

/// The streak statement, and the app's rationed celebration signature.
///
/// Every arrangement shows exactly ONE of these — the hero earns its
/// weight by being rare, so a layout may move it, but never multiply it
/// and never resize it.
///
/// It is deliberately NOT scalable. An earlier version took a maxHeight
/// and `FittedBox`-scaled the whole block to fit, which shrank the type
/// and the sparkles together by the same factor: the result reads as a
/// squashed copy of the hero rather than a smaller one, because type and
/// decoration do not scale at the same rate to the eye. If an
/// arrangement cannot afford the hero at its own size, that arrangement
/// needs to give it room, not shrink it.
class RankStreakHero extends StatelessWidget {
  const RankStreakHero({super.key, required this.weeks});

  final int weeks;

  @override
  Widget build(BuildContext context) {
    return SparkleHero(
      top: 'YOU HAVE A',
      accent: '$weeks WEEK',
      bottom: 'STREAK',
    );
  }
}
