import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/shared/widgets/text/celebration_eyebrow.dart';

// Per-screen layout math, file-scoped per CLAUDE.md's _k carve-out.
// The belt's landing size: exactly 2x `RankHeader`'s 77 x 50 profile belt, so
// the aspect (1.54) and the provenance are both preserved without inventing a
// free number. `RankBody` lands at 77 x 50 because there the belt is a label
// beside a number; here the belt IS the payload, and ending a belt celebration
// on a thumbnail deflates it.
const double _kSlotWidth = 154;
const double _kSlotHeight = 100;

/// The promotion card's settled frame: eyebrow over the landed belt's slot,
/// the new rank's name under it, and the "from" line at the foot.
///
/// It is `RankBody._StatsLayout`'s skeleton verbatim — `Spacer` / centred
/// min-column / `Spacer` / bottom caption — with different children. The belt
/// itself is NOT here: [slotKey] marks an empty box the parent measures, and
/// the parent flies the real belt into it, so the belt stays one rendered
/// object for the whole animation.
///
/// The whole block is faded in by the parent as a single `Opacity`, so nothing
/// inside it self-animates and a skip lands every part of it at once.
class PromotionSettledBlock extends StatelessWidget {
  const PromotionSettledBlock({
    super.key,
    required this.eyebrow,
    required this.newRankName,
    required this.fromLine,
    required this.slotKey,
  });

  /// `YOU'VE BEEN PROMOTED`, or `YOUR FIRST RANK` on a first assignment.
  final String eyebrow;

  /// The leaf the member moved TO. ONE composed display string that may carry
  /// the sub-rank (`Blue Belt · 2 Stripes`) — never split it on the `·`. It is
  /// stacked BELOW the belt rather than beside it (as `RankHeader` does)
  /// because at `h1` that string measures ~250pt, which alongside a 154pt belt
  /// would overflow a 360pt phone. Stacked it has the full content width, and
  /// mark-then-name is what the eye expects of a hero anyway.
  final String newRankName;

  /// `from {old_rank_name}`, or null on a first assignment — there is no from.
  /// Omitted rather than blank: an empty `Text` would reserve a line of `h3`
  /// and push the block off centre, the same guard `RankHeader` and
  /// `RankBody._RankRow` already apply to a blank sub-label.
  final String? fromLine;

  /// Marks the empty box the parent measures and flies the belt into.
  final GlobalKey slotKey;

  @override
  Widget build(BuildContext context) {
    final from = fromLine;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Spacer(),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          spacing: DesignConstants.spacingBig,
          children: [
            CelebrationEyebrow(text: eyebrow),
            SizedBox(key: slotKey, width: _kSlotWidth, height: _kSlotHeight),
            Text(
              newRankName,
              style: DesignConstants.h1,
              textAlign: TextAlign.center,
              // A gym with an unusually long custom rank name WRAPS rather
              // than shrinking — the app does not auto-shrink type anywhere
              // and should not start here.
              maxLines: 2,
            ),
          ],
        ),
        const Spacer(),
        if (from != null)
          Text(
            from,
            textAlign: TextAlign.center,
            style: DesignConstants.h3.copyWith(
              color: DesignConstants.text2nd,
            ),
          ),
      ],
    );
  }
}
