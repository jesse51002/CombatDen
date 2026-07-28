import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';

/// The "Next Rank" heading.
///
/// Its own widget so a layout can place it anywhere the arrangement
/// needs it — beside the badge, under an arc, inside a tile — while the
/// screen still carries exactly one of them.
class NextRankTitle extends StatelessWidget {
  const NextRankTitle({
    super.key,
    required this.title,
    this.align = TextAlign.start,
    this.compact = false,
  });

  final String title;
  final TextAlign align;

  /// Steps the heading down for tight boxes (the tile board).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      textAlign: align,
      style: compact ? DesignConstants.h3 : DesignConstants.h2,
    );
  }
}
