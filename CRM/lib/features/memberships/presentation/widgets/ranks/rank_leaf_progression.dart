import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';

/// The one-line progression label under a promotable member's name:
/// where they are now → where a Promote lands them.
///
/// Reads left to right as "current leaf → next leaf", with the current
/// leaf quiet (context) and the NEXT leaf emphasized (the target the
/// Promote button delivers). At the top of the ladder there is no next
/// leaf: [nextLabel] is null, the arrow drops, and the current leaf
/// becomes the emphasized token trailed by a muted "Top of the ladder"
/// (matching the rank-detail hero's copy).
///
/// Both parts ellipsize; the destination is given the larger share so a
/// long current label yields first.
class RankLeafProgression extends StatelessWidget {
  /// The member's current leaf, e.g. "White Belt · 2 Stripes".
  final String currentLabel;

  /// The leaf a one-step Promote lands on, e.g. "White Belt · 3 Stripes"
  /// or "Blue Belt · Base". Null at the top of the ladder.
  final String? nextLabel;

  const RankLeafProgression({
    super.key,
    required this.currentLabel,
    required this.nextLabel,
  });

  @override
  Widget build(BuildContext context) {
    final next = nextLabel;
    if (next == null) {
      // Top of the ladder: no target, so the current leaf is the subject.
      return Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: currentLabel,
              style: DesignConstants.pSmallSemibold,
            ),
            TextSpan(
              text: '  ·  Top of the ladder',
              style: DesignConstants.pSmall.copyWith(
                color: DesignConstants.text3rd,
              ),
            ),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }

    return Row(
      spacing: DesignConstants.spacingSmall,
      children: [
        Flexible(
          flex: 2,
          child: Text(
            currentLabel,
            style: DesignConstants.pSmall.copyWith(
              color: DesignConstants.text2nd,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Icon(
          Symbols.arrow_forward_sharp,
          size: DesignConstants.iconSizeTiny,
          color: DesignConstants.text3rd,
          weight: DesignConstants.iconWeight,
        ),
        Flexible(
          flex: 3,
          child: Text(
            next,
            style: DesignConstants.pSmallSemibold,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
