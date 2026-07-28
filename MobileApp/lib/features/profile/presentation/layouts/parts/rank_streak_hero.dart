import 'package:flutter/material.dart';
import 'package:mobile_app/shared/widgets/sparkle_hero/sparkle_hero.dart';

/// The streak statement, and the app's rationed celebration signature.
///
/// Every arrangement shows exactly ONE of these — the hero earns its
/// weight by being rare, so a layout may move it, overlay it, or shrink
/// it to a line, but never multiply it.
///
/// [maxHeight] null renders the hero at its own size (what ships).
/// Given a height, the whole block — sparkles included — is scaled down
/// to fit, so the arrangement changes its prominence without touching
/// the hero itself.
class RankStreakHero extends StatelessWidget {
  const RankStreakHero({super.key, required this.weeks, this.maxHeight});

  final int weeks;
  final double? maxHeight;

  @override
  Widget build(BuildContext context) {
    final hero = SparkleHero(
      top: 'YOU HAVE A',
      accent: '$weeks WEEK',
      bottom: 'STREAK',
    );
    final height = maxHeight;
    if (height == null) return hero;
    return SizedBox(
      height: height,
      child: FittedBox(fit: BoxFit.contain, child: hero),
    );
  }
}
