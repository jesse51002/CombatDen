import 'package:flutter/material.dart';
import 'package:mobile_app/shared/widgets/sparkle_hero/sparkle_hero.dart';

/// "You earned 3,400 points" hero block — sparkles surrounding a formatted
/// points total.
class PointsHeadline extends StatelessWidget {
  const PointsHeadline({super.key, required this.points});

  final int points;

  @override
  Widget build(BuildContext context) {
    return SparkleHero(
      top: 'YOU EARNED',
      accent: _formatPoints(points),
      bottom: 'POINTS',
    );
  }
}

String _formatPoints(int n) {
  if (n < 1000) return '$n';
  final s = n.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return buf.toString();
}
