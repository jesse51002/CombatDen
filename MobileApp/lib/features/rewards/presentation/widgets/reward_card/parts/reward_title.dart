import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';

/// Two lines of h2 (16px font, ~1.3 line height). Reserving the slot
/// keeps every card in a grid the same height whether its title runs one
/// line or two.
const double kRewardTitleTwoLine = 42;

/// A reward's title. Exactly one per card in every layout; the line
/// clamp, alignment and reserved height are presentation.
class RewardTitle extends StatelessWidget {
  const RewardTitle({
    super.key,
    required this.title,
    required this.maxLines,
    this.style,
    this.textAlign = TextAlign.center,
    this.reserveHeight,
  });

  final String title;
  final int maxLines;
  final TextStyle? style;
  final TextAlign textAlign;

  /// Fixed slot height, so neighbouring cards line up. Null lets the
  /// title take its intrinsic height (rows, tiles).
  final double? reserveHeight;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      title,
      style: style ?? DesignConstants.h2,
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
    );
    if (reserveHeight == null) return text;
    return SizedBox(
      height: reserveHeight,
      child: Align(alignment: Alignment.topCenter, child: text),
    );
  }
}
