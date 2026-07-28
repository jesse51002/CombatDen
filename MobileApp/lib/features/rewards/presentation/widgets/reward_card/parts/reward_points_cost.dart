import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';

/// What the reward costs in points. Exactly one per reward card in
/// every layout; only its type size and alignment move.
class RewardPointsCost extends StatelessWidget {
  const RewardPointsCost({
    super.key,
    required this.pointsCost,
    this.style,
    this.textAlign = TextAlign.center,
  });

  final int pointsCost;

  /// Presentation only. Defaults to the shipped h2-in-brand treatment.
  final TextStyle? style;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    return Text(
      '${formatRewardPoints(pointsCost)} pts',
      style:
          style ??
          DesignConstants.h2.copyWith(color: DesignConstants.primaryColor),
      textAlign: textAlign,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// Formats a points integer with thousand-separator commas.
String formatRewardPoints(int n) {
  if (n < 1000) return '$n';
  final s = n.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return buf.toString();
}
