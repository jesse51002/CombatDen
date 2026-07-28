import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';

/// The words under the progress indicator — which rank is next and how
/// many classes are left ("Blue Stripe III (23/50 classes)").
///
/// Never truncated: it is the one place the screen says what the
/// progress actually counts, so every layout gives it the room to wrap.
class NextRankProgressLabel extends StatelessWidget {
  const NextRankProgressLabel({
    super.key,
    required this.label,
    this.align = TextAlign.start,
    this.compact = false,
  });

  final String label;
  final TextAlign align;

  /// Steps the label down for tight boxes (the tile board).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final style = compact
        ? DesignConstants.pSmall
        : DesignConstants.h2Regular;
    return Text(
      label,
      textAlign: align,
      style: style.copyWith(color: DesignConstants.text2nd),
    );
  }
}
